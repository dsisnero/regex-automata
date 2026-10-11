require "./spec_helper"

private def pid(id : Int32) : Regex::Automata::PatternID
  Regex::Automata::PatternID.new(id)
end

private def sid(id : Int32) : Regex::Automata::StateID
  Regex::Automata::StateID.new(id)
end

private def s_byte(byte : UInt8, next_id : Int32) : Regex::Automata::NFA::ByteRange
  Regex::Automata::NFA::ByteRange.new(
    Regex::Automata::NFA::Transition.new(byte, byte, sid(next_id))
  )
end

private def s_range(start_byte : UInt8, end_byte : UInt8, next_id : Int32) : Regex::Automata::NFA::ByteRange
  Regex::Automata::NFA::ByteRange.new(
    Regex::Automata::NFA::Transition.new(start_byte, end_byte, sid(next_id))
  )
end

private def s_look(kind : Regex::Automata::NFA::Look::Kind, next_id : Int32) : Regex::Automata::NFA::Look
  Regex::Automata::NFA::Look.new(kind, sid(next_id))
end

private def s_match(pattern_id : Int32, next_id : Int32? = nil) : Regex::Automata::NFA::Match
  Regex::Automata::NFA::Match.new(pid(pattern_id), next_id.try { |id| sid(id) })
end

private def s_cap(next_id : Int32, pattern_id : Int32, group_index : Int32, slot : Int32) : Regex::Automata::NFA::Capture
  Regex::Automata::NFA::Capture.new(sid(next_id), pid(pattern_id), group_index, slot)
end

private def s_bin_union(left : Int32, right : Int32) : Regex::Automata::NFA::BinaryUnion
  Regex::Automata::NFA::BinaryUnion.new(sid(left), sid(right))
end

private def s_union(ids : Array(Int32)) : Regex::Automata::NFA::Union
  Regex::Automata::NFA::Union.new(ids.map { |id| sid(id) })
end

private def s_fail : Regex::Automata::NFA::Fail
  Regex::Automata::NFA::Fail.new
end

private def rust_layout_nfa(pattern : String) : Regex::Automata::NFA::NFA
  Regex::Automata::NFA::NFA.compiler
    .configure(
      Regex::Automata::NFA::NFA.config
        .which_captures(Regex::Automata::NFA::WhichCaptures::None)
        .unanchored_prefix(false)
    )
    .build(pattern)
end

describe Regex::Automata::NFA::NFA do
  it "matches Rust's Thompson compiler graphs for literals, classes, and repetition" do
    rust_layout_nfa("").states.should eq([s_match(0)])
    rust_layout_nfa("a").states.should eq([s_byte('a'.ord.to_u8, 1), s_match(0)])
    rust_layout_nfa("ab").states.should eq([
      s_byte('a'.ord.to_u8, 1), s_byte('b'.ord.to_u8, 2), s_match(0),
    ])
    rust_layout_nfa("[a-z]").states.should eq([s_range('a'.ord.to_u8, 'z'.ord.to_u8, 1), s_match(0)])
    rust_layout_nfa("a?").states.should eq([s_bin_union(1, 2), s_byte('a'.ord.to_u8, 2), s_match(0)])
    rust_layout_nfa("a??").states.should eq([s_bin_union(2, 1), s_byte('a'.ord.to_u8, 2), s_match(0)])
    rust_layout_nfa("ab+").states.should eq([
      s_byte('a'.ord.to_u8, 1), s_byte('b'.ord.to_u8, 2), s_bin_union(1, 3), s_match(0),
    ])
    rust_layout_nfa("a{2,5}").states.should eq([
      s_byte('a'.ord.to_u8, 1), s_byte('a'.ord.to_u8, 2),
      s_bin_union(3, 8), s_byte('a'.ord.to_u8, 4),
      s_bin_union(5, 8), s_byte('a'.ord.to_u8, 6),
      s_bin_union(7, 8), s_byte('a'.ord.to_u8, 8), s_match(0),
    ])
  end

  it "assembles hand-built patterns with Rust builder patch and priority semantics" do
    builder = Regex::Automata::NFA::Builder.new
    builder.get_utf8.should be_false
    builder.get_reverse.should be_false
    builder.pattern_len.should eq(0)

    prefix = builder.add_union_reverse([] of Regex::Automata::StateID)
    any = builder.add_range(Regex::Automata::NFA::Transition.new(0_u8, 255_u8, sid(0)))
    builder.patch(prefix, any)
    builder.patch(any, prefix)
    alt = builder.add_union([] of Regex::Automata::StateID)
    builder.patch(prefix, alt)

    builder.start_pattern.should eq(pid(0))
    first_start = builder.add_capture_start(sid(0), 0_u32, nil)
    first = builder.add_range(Regex::Automata::NFA::Transition.new('a'.ord.to_u8, 'a'.ord.to_u8, sid(0)))
    first_end = builder.add_capture_end(sid(0), 0_u32)
    first_match = builder.add_match
    builder.patch(first_start, first)
    builder.patch(first, first_end)
    builder.patch(first_end, first_match)
    builder.finish_pattern(first_start).should eq(pid(0))

    builder.start_pattern.should eq(pid(1))
    second_start = builder.add_capture_start(sid(0), 0_u32, nil)
    second = builder.add_range(Regex::Automata::NFA::Transition.new('b'.ord.to_u8, 'b'.ord.to_u8, sid(0)))
    second_end = builder.add_capture_end(sid(0), 0_u32)
    second_match = builder.add_match
    builder.patch(second_start, second)
    builder.patch(second, second_end)
    builder.patch(second_end, second_match)
    builder.finish_pattern(second_start).should eq(pid(1))
    builder.patch(alt, first_start)
    builder.patch(alt, second_start)

    nfa = builder.build(alt, prefix)
    nfa.pattern_len.should eq(2)
    nfa.start_pattern(pid(0)).should_not be_nil
    vm = Regex::Automata::NFA::PikeVM.new_from_nfa(nfa)
    vm.find(vm.create_cache, "xxb").should eq(Regex::Automata::Match.must(1, 2...3))

    builder.clear
    builder.pattern_len.should eq(0)
    builder.memory_usage.should eq(0_i64)
  end

  it "reverses hand-built union priority at final assembly" do
    builder = Regex::Automata::NFA::Builder.new
    alt = builder.add_union_reverse([] of Regex::Automata::StateID)
    first = builder.add_fail
    second = builder.add_fail
    builder.patch(alt, first)
    builder.patch(alt, second)
    nfa = builder.build(alt, alt)
    state = nfa.state(nfa.start_anchored).as(Regex::Automata::NFA::BinaryUnion)
    state.alt1.should eq(sid(2))
    state.alt2.should eq(sid(1))
  end

  it "checks memory added by a union patch and retains configuration after clear" do
    builder = Regex::Automata::NFA::Builder.new
    matcher = Regex::Automata::LookMatcher.new
    matcher.set_line_terminator(0_u8)
    builder.set_look_matcher(matcher)
    builder.set_utf8(true)
    builder.set_reverse(true)
    builder.set_size_limit(32_i64)
    union = builder.add_union([] of Regex::Automata::StateID)
    builder.memory_usage.should eq(32_i64)
    expect_raises(Regex::Automata::NFA::BuildError) { builder.patch(union, sid(0)) }
    builder.get_size_limit.should eq(32_i64)
    builder.clear
    builder.get_utf8.should be_true
    builder.get_reverse.should be_true
    builder.get_look_matcher.get_line_terminator.should eq(0_u8)
    builder.get_size_limit.should eq(32_i64)
    builder.memory_usage.should eq(0_i64)
  end

  it "reports duplicate hand-built capture names at build time" do
    builder = Regex::Automata::NFA::Builder.new
    builder.start_pattern
    start = builder.add_capture_start(sid(0), 0_u32, nil)
    builder.add_capture_start(sid(0), 1_u32, "name")
    builder.add_capture_start(sid(0), 2_u32, "name")
    builder.finish_pattern(start)
    error = expect_raises(Regex::Automata::NFA::BuildError) { builder.build(start, start) }
    error.kind.should eq(Regex::Automata::NFA::BuildError::Kind::Captures)
  end

  it "enforces hand-builder pattern and sparse transition invariants" do
    builder = Regex::Automata::NFA::Builder.new
    expect_raises(Exception, "must call 'start_pattern' first") { builder.add_match }
    builder.start_pattern.should eq(pid(0))
    expect_raises(Exception, "must call 'finish_pattern' first") { builder.start_pattern }
    expect_raises(Regex::Automata::NFA::BuildError) do
      builder.add_capture_start(sid(0), Regex::Automata::SmallIndex::LIMIT.to_u32, nil)
    end
    expect_raises(ArgumentError) do
      builder.add_sparse([
        Regex::Automata::NFA::Transition.new(1_u8, 5_u8, sid(0)),
        Regex::Automata::NFA::Transition.new(5_u8, 9_u8, sid(0)),
      ])
    end
    empty = builder.add_empty
    look = builder.add_look(empty, Regex::Automata::NFA::Look::Kind::StartText)
    builder.patch(empty, look)
    builder.finish_pattern(look)
    builder.pattern_len.should eq(1)
  end

  it "merges Thompson compiler configuration as sparse overrides" do
    base = Regex::Automata::NFA::NFA.config.utf8(false).shrink(true)
    base.overwrite(Regex::Automata::NFA::NFA.config).get_utf8.should be_false
    base.overwrite(Regex::Automata::NFA::NFA.config).get_shrink.should be_true
    base.overwrite(Regex::Automata::NFA::NFA.config.utf8(true)).get_utf8.should be_true
  end

  it "exposes Thompson compiler config and public constructors" do
    lookm = Regex::Automata::LookMatcher.new
    lookm.set_line_terminator(0_u8)

    config = Regex::Automata::NFA::NFA.config
      .utf8(false)
      .reverse(true)
      .nfa_size_limit(123_i64)
      .shrink(true)
      .which_captures(Regex::Automata::NFA::WhichCaptures::Implicit)
      .look_matcher(lookm)

    config.get_utf8.should be_false
    config.get_reverse.should be_true
    config.get_nfa_size_limit.should eq(123_i64)
    config.get_shrink.should be_true
    config.get_which_captures.should eq(Regex::Automata::NFA::WhichCaptures::Implicit)
    config.get_look_matcher.get_line_terminator.should eq(0_u8)

    compiler = Regex::Automata::NFA::NFA.compiler
    compiler.configure(config).should be(compiler)
    compiler.syntax(Regex::Automata::Syntax::Config.new.utf8(false)).should be(compiler)

    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .utf8(false)
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .syntax(Regex::Automata::Syntax::Config.new.utf8(false))
      .build("(?-u)\\xFF")
    nfa.is_utf8.should be_false
    nfa.pattern_len.should eq(1)
  end

  it "reports NFA size-limit failures through BuildError introspection" do
    error = expect_raises(Regex::Automata::BuildError) do
      Regex::Automata::NFA::NFA.compiler
        .configure(Regex::Automata::NFA::NFA.config.nfa_size_limit(0_i64))
        .build("abc")
    end

    error.is_size_limit_exceeded.should be_true
    error.size_limit.should eq(0_i64)
  end

  it "enforces the NFA size limit while states are added" do
    builder = Regex::Automata::NFA::Builder.new(size_limit: 0_i64)
    expect_raises(Regex::Automata::NFA::BuildError) do
      builder.add_state(Regex::Automata::NFA::Fail.new)
    end

    accumulated = Regex::Automata::NFA::Builder.new
    accumulated.add_state(Regex::Automata::NFA::Fail.new)
    expect_raises(Regex::Automata::NFA::BuildError) do
      accumulated.set_size_limit(0_i64)
    end
  end

  it "enforces the NFA size limit when repetition patching grows a union" do
    error = expect_raises(Regex::Automata::NFA::BuildError) do
      Regex::Automata::NFA::NFA.compiler
        .configure(
          Regex::Automata::NFA::NFA.config
            .which_captures(Regex::Automata::NFA::WhichCaptures::None)
            .unanchored_prefix(false)
            .nfa_size_limit(128_i64)
        )
        .build("a?")
    end
    error.kind.should eq(Regex::Automata::NFA::BuildError::Kind::ExceededSizeLimit)
  end

  it "uses Thompson-specific error variants for parser, size-limit, and reverse-capture failures" do
    syntax = expect_raises(Regex::Automata::NFA::BuildError) do
      Regex::Automata::NFA::NFA.new("(")
    end
    syntax.kind.should eq(Regex::Automata::NFA::BuildError::Kind::Syntax)
    syntax.message.should eq("error parsing regex")
    syntax.source.should_not be_nil

    size = expect_raises(Regex::Automata::NFA::BuildError) do
      Regex::Automata::NFA::NFA.compiler
        .configure(Regex::Automata::NFA::NFA.config.nfa_size_limit(0_i64))
        .build("abc")
    end
    size.kind.should eq(Regex::Automata::NFA::BuildError::Kind::ExceededSizeLimit)
    size.message.should eq("heap usage during NFA compilation exceeded limit of 0")

    captures = expect_raises(Regex::Automata::NFA::BuildError) do
      Regex::Automata::NFA::NFA.compiler
        .configure(Regex::Automata::NFA::NFA.config.reverse(true))
        .build("abc")
    end
    captures.kind.should eq(Regex::Automata::NFA::BuildError::Kind::UnsupportedCaptures)
    captures.message.should eq("currently captures must be disabled when compiling a reverse NFA")

    patterns = Regex::Automata::NFA::BuildError.too_many_patterns(
      Regex::Automata::PatternID::LIMIT
    )
    patterns.kind.should eq(Regex::Automata::NFA::BuildError::Kind::TooManyPatterns)
    patterns.message.not_nil!.should contain("which exceeds the limit")

    states = Regex::Automata::NFA::BuildError.too_many_states(
      Regex::Automata::StateID::LIMIT
    )
    states.kind.should eq(Regex::Automata::NFA::BuildError::Kind::TooManyStates)
    states.message.not_nil!.should contain("which exceeds the limit")
  end

  it "builds always-match and never-match NFAs" do
    always = Regex::Automata::NFA::NFA.always_match
    always.pattern_len.should eq(1)
    always.has_capture.should be_true
    always.has_empty.should be_true
    always.start_pattern(pid(0)).should eq(always.start_anchored)
    always.state(always.start_anchored).should eq(s_cap(1, 0, 0, 0))
    always.states.should eq([
      s_cap(1, 0, 0, 0),
      s_cap(2, 0, 0, 1),
      s_match(0),
    ])

    never = Regex::Automata::NFA::NFA.never_match
    never.pattern_len.should eq(0)
    never.has_capture.should be_false
    never.has_empty.should be_false
    never.start_pattern(pid(0)).should be_nil
    never.states.should eq([s_fail])
  end

  it "builds reverse Unicode classes with bounded suffix-cache semantics" do
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .reverse(true)
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .build("[α-ω]+")

    nfa.reverse?.should be_true
    nfa.states.should_not be_empty
  end

  it "preserves leftmost-first semantics for prefix-overlapping literal tries" do
    shortest = Regex::Automata::NFA::PikeVM.new("(?:sam|samwise)")
    cache = shortest.create_cache
    shortest.find(cache, "samwise").should eq(Regex::Automata::Match.must(0, 0...3))

    boundary = Regex::Automata::NFA::PikeVM.new("\\b(?:sam|samwise)\\b")
    cache = boundary.create_cache
    boundary.find(cache, "samwise").should eq(Regex::Automata::Match.must(0, 0...7))

    longest = Regex::Automata::NFA::PikeVM.new("(?:zapper|z|zap)")
    cache = longest.create_cache
    longest.find(cache, "zapper").should eq(Regex::Automata::Match.must(0, 0...6))
  end

  it "matches always-match and never-match NFAs through PikeVM over ranged input" do
    always = Regex::Automata::NFA::PikeVM.new_from_nfa(Regex::Automata::NFA::NFA.always_match)
    always_cache = always.create_cache
    always_caps = always.create_captures
    always_find = ->(haystack : String, start : Int32, finish : Int32) do
      input = Regex::Automata::Input.new(haystack).range(start...finish)
      always.search(always_cache, input, always_caps)
      always_caps.get_match.try(&.end)
    end

    always_find.call("", 0, 0).should eq(0)
    always_find.call("a", 0, 1).should eq(0)
    always_find.call("a", 1, 1).should eq(1)
    always_find.call("ab", 0, 2).should eq(0)
    always_find.call("ab", 1, 2).should eq(1)
    always_find.call("ab", 2, 2).should eq(2)

    never = Regex::Automata::NFA::PikeVM.new_from_nfa(Regex::Automata::NFA::NFA.never_match)
    never_cache = never.create_cache
    never_caps = never.create_captures
    never_find = ->(haystack : String, start : Int32, finish : Int32) do
      input = Regex::Automata::Input.new(haystack).range(start...finish)
      never.search(never_cache, input, never_caps)
      never_caps.get_match.try(&.end)
    end

    never_find.call("", 0, 0).should be_nil
    never_find.call("a", 0, 1).should be_nil
    never_find.call("a", 1, 1).should be_nil
    never_find.call("ab", 0, 2).should be_nil
    never_find.call("ab", 1, 2).should be_nil
    never_find.call("ab", 2, 2).should be_nil
  end

  it "adds the unanchored prefix when compiling unanchored patterns" do
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .build("a")

    nfa.states.should eq([
      s_bin_union(2, 1),
      s_range(0_u8, 255_u8, 0),
      s_byte('a'.ord.to_u8, 3),
      s_match(0),
    ])
    nfa.start_anchored.should eq(sid(2))
    nfa.start_unanchored.should eq(sid(0))
    nfa.start_pattern(pid(0)).should eq(sid(2))
    nfa.is_always_start_anchored.should be_false
  end

  it "omits the unanchored prefix for start-anchored patterns" do
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .build("^a")

    nfa.start_anchored.should eq(nfa.start_unanchored)
    nfa.is_always_start_anchored.should be_true
    nfa.state(nfa.start_anchored).should be_a(Regex::Automata::NFA::Look)
    nfa.look_set_any.contains_anchor.should be_true
    nfa.look_set_prefix_any.contains_anchor.should be_true
    nfa.look_set_prefix_all.contains_anchor.should be_true
  end

  it "keeps the unanchored prefix for end-anchored patterns" do
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .build("a$")

    nfa.state(nfa.start_unanchored).should eq(s_bin_union(2, 1))
    nfa.look_set_any.contains_anchor.should be_true
    nfa.look_set_prefix_any.should be_empty
    nfa.look_set_prefix_all.should be_empty
  end

  it "tracks per-pattern starts for multi-pattern compilation" do
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
          .unanchored_prefix(false)
      )
      .build_many(["a", "b"])

    nfa.states.should eq([
      s_byte('a'.ord.to_u8, 1),
      s_match(0),
      s_byte('b'.ord.to_u8, 3),
      s_match(1),
      s_bin_union(0, 2),
    ])
    nfa.pattern_len.should eq(2)
    nfa.patterns.to_a.should eq([pid(0), pid(1)])
    nfa.start_anchored.should eq(sid(4))
    nfa.start_unanchored.should eq(sid(4))
    nfa.start_pattern(pid(0)).should eq(sid(0))
    nfa.start_pattern(pid(1)).should eq(sid(2))
    nfa.start_pattern(pid(2)).should be_nil
  end

  it "supports all implicit and no capture policies" do
    all = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .unanchored_prefix(false)
          .which_captures(Regex::Automata::NFA::WhichCaptures::All)
      )
      .build("a(b)c")
    all.has_capture.should be_true
    all.group_info.all_group_len.should eq(2)
    all.states.select(&.is_a?(Regex::Automata::NFA::Capture)).map(&.as(Regex::Automata::NFA::Capture).slot).sort.should eq([0, 1, 2, 3])
    all.states.should eq([
      s_cap(1, 0, 0, 0), s_byte('a'.ord.to_u8, 2),
      s_cap(3, 0, 1, 2), s_byte('b'.ord.to_u8, 4),
      s_cap(5, 0, 1, 3), s_byte('c'.ord.to_u8, 6),
      s_cap(7, 0, 0, 1), s_match(0),
    ])

    implicit = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .unanchored_prefix(false)
          .which_captures(Regex::Automata::NFA::WhichCaptures::Implicit)
      )
      .build("a(b)c")
    implicit.group_info.all_group_len.should eq(1)
    implicit.states.select(&.is_a?(Regex::Automata::NFA::Capture)).map(&.as(Regex::Automata::NFA::Capture).slot).sort.should eq([0, 1])
    implicit.states.should eq([
      s_cap(1, 0, 0, 0), s_byte('a'.ord.to_u8, 2),
      s_byte('b'.ord.to_u8, 3), s_byte('c'.ord.to_u8, 4),
      s_cap(5, 0, 0, 1), s_match(0),
    ])

    none = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .unanchored_prefix(false)
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .build("a(b)c")
    none.has_capture.should be_false
    none.group_info.all_group_len.should eq(0)
    none.states.should eq([
      s_byte('a'.ord.to_u8, 1), s_byte('b'.ord.to_u8, 2),
      s_byte('c'.ord.to_u8, 3), s_match(0),
    ])
  end
end
