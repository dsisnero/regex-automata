require "./spec_helper"

# Pinned oracle: regex-automata/src/nfa/thompson/builder.rs::Builder::build
# and nfa.rs::Inner::remap. An untouched builder's zero start ID cannot be
# remapped through its empty state table, so Rust panics.
describe "pinned Thompson builder finalization contracts" do
  it "rejects an untouched builder's unmappable start state" do
    builder = Regex::Automata::NFA::Builder.new
    expect_raises(IndexError) do
      builder.build(Regex::Automata::StateID::ZERO, Regex::Automata::StateID::ZERO)
    end
  end

  it "keeps same-named captures distinct across hand-built patterns" do
    b = Regex::Automata::NFA::Builder.new
    zero = Regex::Automata::StateID::ZERO
    prefix = b.add_union_reverse([] of Regex::Automata::StateID)
    any = b.add_range(Regex::Automata::NFA::Transition.new(0_u8, 255_u8, zero))
    b.patch(prefix, any)
    b.patch(any, prefix)
    alt = b.add_union([] of Regex::Automata::StateID)
    b.patch(prefix, alt)

    starts = [] of Regex::Automata::StateID
    [{97_u8, 122_u8}, {65_u8, 90_u8}].each do |first, last|
      b.start_pattern
      start = b.add_capture_start(zero, 0_u32, nil)
      named_start = b.add_capture_start(zero, 1_u32, "foo")
      range = b.add_range(Regex::Automata::NFA::Transition.new(first, last, zero))
      named_end = b.add_capture_end(zero, 1_u32)
      finish = b.add_capture_end(zero, 0_u32)
      match = b.add_match
      b.patch(start, named_start)
      b.patch(named_start, range)
      b.patch(range, named_end)
      b.patch(named_end, finish)
      b.patch(finish, match)
      b.finish_pattern(start)
      starts << start
    end
    starts.each { |start| b.patch(alt, start) }
    vm = Regex::Automata::NFA::PikeVM.new_from_nfa(b.build(alt, prefix))
    caps = vm.captures_iter(vm.create_cache, "0123aAaAA").to_a
    caps.size.should eq(5)
    [0, 1, 0, 1, 1].each_with_index do |pattern, index|
      caps[index].pattern.should eq(Regex::Automata::PatternID.new(pattern))
      caps[index].get_group_by_name("foo").should eq(Regex::Automata::Span.new(index + 4, index + 5))
    end
  end

  it "appends union patches without copying the growing transition vector" do
    b = Regex::Automata::NFA::Builder.new
    union = b.add_union([] of Regex::Automata::StateID)
    alternates = b.state(union).as(Regex::Automata::NFA::Union).alternates
    32.times { |index| b.patch(union, Regex::Automata::StateID.new(index)) }
    b.state(union).as(Regex::Automata::NFA::Union).alternates.should be(alternates)
    alternates.size.should eq(32)
  end

  it "rejects an earlier pattern with missing capture groups before a captured pattern" do
    b = Regex::Automata::NFA::Builder.new
    b.start_pattern
    first = b.add_match
    b.finish_pattern(first)
    b.start_pattern
    second = b.add_capture_start(Regex::Automata::StateID::ZERO, 0_u32, nil)
    finish = b.add_match
    b.patch(second, finish)
    b.finish_pattern(second)
    union = b.add_union([first, second])
    error = expect_raises(Regex::Automata::NFA::BuildError) { b.build(union, union) }
    error.kind.should eq(Regex::Automata::NFA::BuildError::Kind::Captures)
  end

  it "reports capture errors before malformed start-state remapping" do
    b = Regex::Automata::NFA::Builder.new
    b.start_pattern
    start = b.add_capture_start(Regex::Automata::StateID::ZERO, 0_u32, nil)
    b.add_capture_start(Regex::Automata::StateID::ZERO, 1_u32, "same")
    b.add_capture_start(Regex::Automata::StateID::ZERO, 2_u32, "same")
    b.finish_pattern(start)
    invalid = Regex::Automata::StateID.new(100)
    error = expect_raises(Regex::Automata::NFA::BuildError) { b.build(invalid, invalid) }
    error.kind.should eq(Regex::Automata::NFA::BuildError::Kind::Captures)
  end

  it "keeps Rust's patch mutation and error ordering" do
    b = Regex::Automata::NFA::Builder.new
    fail_state = b.add_fail
    b.patch(fail_state, fail_state)
    b.state(fail_state).should be_a(Regex::Automata::NFA::Fail)
    sparse = b.add_sparse([Regex::Automata::NFA::Transition.new('a'.ord.to_u8, 'a'.ord.to_u8, fail_state)])
    expect_raises(Exception, "cannot patch from a sparse NFA state") { b.patch(sparse, fail_state) }

    union = b.add_union([] of Regex::Automata::StateID)
    before = b.memory_usage
    b.set_size_limit(before)
    expect_raises(Regex::Automata::NFA::BuildError) { b.patch(union, fail_state) }
    b.state(union).as(Regex::Automata::NFA::Union).alternates.should eq([fail_state])
    b.memory_usage.should be > before
  end
end

# Pinned error.rs::std::error::Error::source returns an underlying error only
# for Syntax and Captures; Word deliberately returns None.
describe "pinned Thompson BuildError source contracts" do
  it "exposes only syntax and capture causes" do
    cause = Exception.new("vendor cause")
    Regex::Automata::NFA::BuildError.syntax(cause).source.should be(cause)
    Regex::Automata::NFA::BuildError.captures(cause).source.should be(cause)
    Regex::Automata::NFA::BuildError.word(cause).source.should be_nil
  end

  it "preserves Rust's remaining variant messages and size-limit introspection" do
    error = Regex::Automata::NFA::BuildError.invalid_capture_index(7_u32)
    error.message.should eq("capture group index 7 is invalid (too big or discontinuous)")
    error.source.should be_nil
    error.size_limit.should be_nil

    word = Regex::Automata::NFA::BuildError.word(Exception.new("word"))
    word.message.should eq("NFA contains Unicode word boundary")
    word.source.should be_nil

    limit = Regex::Automata::NFA::BuildError.exceeded_size_limit(123_i64)
    limit.message.should eq("heap usage during NFA compilation exceeded limit of 123")
    limit.size_limit.should eq(123_i64)
    limit.source.should be_nil
  end
end

# Exact examples in pinned nfa.rs for the public metadata queries. These
# exercise graph properties, not a Crystal-only reconstruction of expected IDs.
describe "pinned Thompson NFA metadata doctests" do
  it "reports the upstream empty-match examples" do
    {"" => true, "a+" => false, "a*" => true, "(a+)*" => true,
     "\\b+" => true, "foo|(bar)?|quux" => true,
     "[a&&b]" => false, "[a&&b]*" => true, "[a&&b]+" => false}.each do |pattern, expected|
      Regex::Automata::NFA::NFA.new(pattern).has_empty.should eq(expected)
    end
  end

  it "reports the upstream anchored-start examples" do
    {"a" => false, "^a" => true, "(?m)^a" => false,
     "(^a)|a" => false}.each do |pattern, expected|
      Regex::Automata::NFA::NFA.new(pattern).is_always_start_anchored.should eq(expected)
    end
    Regex::Automata::NFA::NFA.new_many(["^a", "^b", "^c"]).is_always_start_anchored.should be_true
    Regex::Automata::NFA::NFA.new_many(["^a", "b", "^c"]).is_always_start_anchored.should be_false
  end

  it "preserves per-pattern starts and prefix versus global look sets" do
    nfa = Regex::Automata::NFA::NFA.new_many(["^a", "^b"])
    nfa.start_anchored.should eq(nfa.start_unanchored)
    nfa.start_pattern(Regex::Automata::PatternID.new(0)).should_not eq(nfa.start_anchored)
    nfa.start_pattern(Regex::Automata::PatternID.new(1)).should_not eq(nfa.start_anchored)
    nfa.start_pattern(Regex::Automata::PatternID.new(2)).should be_nil

    look_nfa = Regex::Automata::NFA::NFA.new_many(["a", "b", "^ab$", "c"])
    look_nfa.look_set_any.contains(Regex::Automata::Look::Start).should be_true
    look_nfa.look_set_any.contains(Regex::Automata::Look::End).should be_true
    look_nfa.look_set_prefix_any.contains(Regex::Automata::Look::Start).should be_true
    look_nfa.look_set_prefix_any.contains(Regex::Automata::Look::End).should be_false

    mixed = Regex::Automata::NFA::NFA.new_many(["\\b", "^a", "x"])
    mixed.has_empty.should be_true
    mixed.look_set_prefix_any.contains(Regex::Automata::Look::WordUnicode).should be_true
    mixed.look_set_prefix_any.contains(Regex::Automata::Look::Start).should be_true
  end

  it "keeps Rust's pattern iterator and byte-equivalence examples" do
    nfa = Regex::Automata::NFA::NFA.new_many(["[0-9]+", "[a-z]+", "[A-Z]+"])
    nfa.patterns.to_a.should eq((0..2).map { |id| Regex::Automata::PatternID.new(id) })
    nfa.pattern_len.should eq(3)
    Regex::Automata::NFA::NFA.never_match.pattern_len.should eq(0)
    Regex::Automata::NFA::NFA.always_match.pattern_len.should eq(1)
    # Both Rust constructors use Builder::new without enabling UTF-8.
    Regex::Automata::NFA::NFA.always_match.is_utf8.should be_false
    Regex::Automata::NFA::NFA.never_match.is_utf8.should be_false

    classes = Regex::Automata::NFA::NFA.new("[a-z]+").byte_classes
    classes.get('a'.ord.to_u8).should eq(classes.get('z'.ord.to_u8))
    classes.get('a'.ord.to_u8).should_not eq(classes.get('A'.ord.to_u8))
  end

  it "preserves reverse and look-matcher metadata from the compiler" do
    matcher = Regex::Automata::LookMatcher.new
    matcher.set_line_terminator(0_u8)
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(Regex::Automata::NFA::NFA.config
        .reverse(true)
        .which_captures(Regex::Automata::NFA::WhichCaptures::None)
        .look_matcher(matcher))
      .build("a")
    nfa.is_reverse.should be_true
    nfa.look_matcher.get_line_terminator.should eq(0_u8)
  end

  it "retains the Rust byte-class set for downstream DFA construction" do
    nfa = Regex::Automata::NFA::NFA.new("[a-z]+")
    nfa.byte_class_set.byte_classes.should eq(nfa.byte_classes)
    quit = Regex::Automata::ByteSet.empty.add('q'.ord.to_u8)
    extended = nfa.byte_class_set.dup
    extended.add_set(quit)
    classes = extended.byte_classes
    classes.get('q'.ord.to_u8).should_not eq(classes.get('p'.ord.to_u8))
    nfa.byte_classes.get('q'.ord.to_u8).should eq(nfa.byte_classes.get('p'.ord.to_u8))
    nfa.byte_class_set.byte_classes.should eq(nfa.byte_classes)
  end

  it "does not let callers mutate the finalized NFA's class boundaries" do
    nfa = Regex::Automata::NFA::NFA.new("[a-z]+")
    quit = Regex::Automata::ByteSet.empty.add('q'.ord.to_u8)
    nfa.byte_class_set.add_set(quit)
    nfa.byte_class_set.byte_classes.should eq(nfa.byte_classes)
  end
end
