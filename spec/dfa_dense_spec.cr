require "./spec_helper"

private def write_u32_le(bytes : Bytes, offset : Int32, value : UInt32) : Nil
  bytes[offset] = (value & 0xFF).to_u8
  bytes[offset + 1] = ((value >> 8) & 0xFF).to_u8
  bytes[offset + 2] = ((value >> 16) & 0xFF).to_u8
  bytes[offset + 3] = ((value >> 24) & 0xFF).to_u8
end

describe "DFA::Dense" do
  it "enumerates dense and sparse materialized state transitions" do
    state = Regex::Automata::DFA::State.new(Regex::Automata::StateID.new(7), 5)
    state.id.should eq(Regex::Automata::StateID.new(7))
    state.set_transition(1, Regex::Automata::StateID.new(3))
    state.set_transition(2, Regex::Automata::StateID.new(3))
    state.set_transition(4, Regex::Automata::StateID.new(4))

    state.transitions.should eq([
      {0, Regex::Automata::DFA::DEAD_STATE_ID},
      {1, Regex::Automata::StateID.new(3)},
      {2, Regex::Automata::StateID.new(3)},
      {3, Regex::Automata::DFA::DEAD_STATE_ID},
      {4, Regex::Automata::StateID.new(4)},
    ])
    state.sparse_transitions.should eq([
      {1, 2, Regex::Automata::StateID.new(3)},
      {4, 4, Regex::Automata::StateID.new(4)},
    ])
  end

  it "returns a dense match state pattern slice" do
    dfa = Regex::Automata::DFA::DFA.new_many(["a", "a"])
    state = dfa.next_eoi_state(dfa.next_state(dfa.start, 'a'.ord.to_u8))
    dfa.pattern_id_slice(state).should eq([Regex::Automata::PatternID.new(0), Regex::Automata::PatternID.new(1)])
  end

  it "round trips dense DFA flag bits" do
    flags = Regex::Automata::DFAFlags.new(has_empty: true, is_utf8: true, is_always_start_anchored: true)
    decoded = Regex::Automata::DFAFlags.from_u32(flags.to_u32)
    decoded.has_empty.should be_true
    decoded.is_utf8.should be_true
    decoded.is_always_start_anchored.should be_true
    decoded.is_anchored.should be_false
  end

  it "requires premultiplied IDs for transition-table validity" do
    classes = Regex::Automata::ByteClasses.empty
    table = Regex::Automata::TransitionTable.new(classes, 2, 2)

    table.is_valid(Regex::Automata::StateID.new(0)).should be_true
    table.is_valid(Regex::Automata::StateID.new(4)).should be_true
    table.is_valid(Regex::Automata::StateID.new(1)).should be_false
    table.is_valid(Regex::Automata::StateID.new(5)).should be_false
    table.is_valid(Regex::Automata::StateID.new(8)).should be_false
  end

  it "rejects malformed dense transition-table bytes" do
    expect_raises(Regex::Automata::DeserializeError) do
      Regex::Automata::TransitionTable.from_bytes(Bytes.new(7))
    end

    classes = Regex::Automata::ByteClasses.empty
    table = Regex::Automata::TransitionTable.new(classes, 1, 2)
    source = table.to_bytes
    source[4] = 0_u8
    source[5] = 0_u8
    source[6] = 0_u8
    source[7] = 0_u8
    expect_raises(Regex::Automata::DeserializeError) do
      Regex::Automata::TransitionTable.from_bytes(source)
    end

    source = table.to_bytes
    source[264] = 1_u8
    expect_raises(Regex::Automata::DeserializeError) do
      Regex::Automata::TransitionTable.from_bytes(source)
    end
  end

  it "round trips dense transition-table bytes from an unaligned slice" do
    classes = Regex::Automata::ByteClasses.empty
    table = Regex::Automata::TransitionTable.new(classes, 1, 2)
    table.set_transition_by_class(Regex::Automata::StateID.new(0), 0, Regex::Automata::StateID.new(2))

    encoded = table.to_bytes
    padded = Bytes.new(encoded.size + 1)
    encoded.copy_to(padded[1, encoded.size])

    decoded = Regex::Automata::TransitionTable.from_bytes(padded[1, encoded.size])
    decoded.next_state_by_class(Regex::Automata::StateID.new(0), 0).should eq(Regex::Automata::StateID.new(2))
  end

  it "builds and truncates owned dense transition rows" do
    table = Regex::Automata::TransitionTable.minimal(Regex::Automata::ByteClasses.empty)

    table.len.should eq(2)
    table.next_state_by_class(Regex::Automata::StateID.new(0), 0).should eq(Regex::Automata::DFA::DEAD_STATE_ID)
    table.next_state_by_class(Regex::Automata::StateID.new(2), 0).should eq(Regex::Automata::DFA::DEAD_STATE_ID)

    added = table.add_empty_state
    added.should eq(Regex::Automata::StateID.new(4))
    table.len.should eq(3)
    table.truncate(2)
    table.len.should eq(2)
    table.is_valid(added).should be_false
  end

  it "validates and serializes owned dense transition mutations" do
    table = Regex::Automata::TransitionTable.minimal(Regex::Automata::ByteClasses.empty)
    dead = Regex::Automata::DFA::DEAD_STATE_ID
    quit = Regex::Automata::StateID.new(2)

    table.set(dead, Regex::Automata::Unit.eoi(1), quit)
    table.next_eoi_state(dead).should eq(quit)
    expect_raises(ArgumentError, /invalid 'to' state/) do
      table.set(dead, Regex::Automata::Unit.eoi(1), Regex::Automata::StateID.new(1))
    end

    bytes = Bytes.new(table.write_to_len)
    table.write_to(bytes).should eq(bytes.size)
    Regex::Automata::TransitionTable.from_bytes(bytes).next_eoi_state(dead).should eq(quit)
    expect_raises(Regex::Automata::SerializeError) do
      table.write_to(Bytes.new(bytes.size - 1))
    end

    table.set_transition_by_class(dead, 0, quit)
    table.swap(dead, quit)
    table.next_state_by_class(quit, 0).should eq(quit)
    table.remap(quit) { dead }
    table.next_state_by_class(quit, 0).should eq(dead)
    table.prev_state_id(quit).should eq(dead)
    table.next_state_id(dead).should eq(quit)

    copy = table.to_owned
    copy.table_mut[0] = quit
    table.table[0].should eq(dead)
  end

  it "validates and copies flattened dense match states" do
    states = Array(Regex::Automata::DFA::State).new
    dead = Regex::Automata::DFA::DEAD_STATE_ID
    states << Regex::Automata::DFA::State.new(dead, 2)
    matched = Regex::Automata::DFA::State.new(Regex::Automata::StateID.new(1), 2)
    matched.add_match(Regex::Automata::PatternID.new(1))
    states << matched

    matches = Regex::Automata::MatchStates.from_states(states, nil, 2)
    matches.match_state?(Regex::Automata::StateID.new(1)).should be_true
    matches.len.should eq(1)
    matches.pattern_len(0).should eq(1)
    matches.pattern_id(0, 0).should eq(Regex::Automata::PatternID.new(1))
    matches.pattern_id_slice(0).should eq([Regex::Automata::PatternID.new(1)])
    matches.pattern_ids.should eq([Regex::Automata::PatternID.new(1)])
    matches.slices.should eq([{0, 1}])
    matches.match_pattern(Regex::Automata::StateID.new(1), 0).should eq(Regex::Automata::PatternID.new(1))
    matches.memory_usage.should eq(12)
    matches.validate.should be_nil

    copy = matches.to_owned
    copy.object_id.should_not eq(matches.object_id)
    copy.match_pattern(Regex::Automata::StateID.new(1), 0).should eq(Regex::Automata::PatternID.new(1))
  end

  it "exposes dense config defaults and upstream-style getters" do
    config = Regex::Automata::DFA::DFA.config

    config.get_accelerate.should be_true
    config.get_minimize.should be_false
    config.get_match_kind.should eq(Regex::Automata::MatchKind::LeftmostFirst)
    config.get_starts.should eq(Regex::Automata::StartKind::Both)
    config.get_starts_for_each_pattern.should be_false
    config.get_byte_classes.should be_true
    config.get_unicode_word_boundary.should be_false
    config.get_quit('x'.ord.to_u8).should be_false
    config.get_specialize_start_states.should be_false
    config.get_dfa_size_limit.should be_nil
    config.get_determinize_size_limit.should be_nil
  end

  it "tracks dense config overrides through compatibility getters" do
    config = Regex::Automata::DFA::DFA.config
      .accelerate(false)
      .minimize(true)
      .match_kind(Regex::Automata::MatchKind::All)
      .start_kind(Regex::Automata::StartKind::Anchored)
      .starts_for_each_pattern(true)
      .byte_classes(false)
      .unicode_word_boundary(true)
      .quit('x'.ord.to_u8, true)
      .specialize_start_states(true)
      .dfa_size_limit(123_i64)
      .determinize_size_limit(456_i64)

    config.get_accelerate.should be_false
    config.get_minimize.should be_true
    config.get_match_kind.should eq(Regex::Automata::MatchKind::All)
    config.get_starts.should eq(Regex::Automata::StartKind::Anchored)
    config.get_starts_for_each_pattern.should be_true
    config.get_byte_classes.should be_false
    config.get_unicode_word_boundary.should be_true
    config.get_quit('x'.ord.to_u8).should be_true
    config.get_specialize_start_states.should be_true
    config.get_dfa_size_limit.should eq(123_i64)
    config.get_determinize_size_limit.should eq(456_i64)
  end

  it "reports whether per-pattern starts were materialized" do
    ordinary = Regex::Automata::DFA::DFA.new_many(["abc", "def"])
    ordinary.starts_for_each_pattern?.should be_false

    specialized = Regex::Automata::DFA::DFA.builder
      .configure { |config| config.starts_for_each_pattern(true) }
      .build_many(["abc", "def"])
    specialized.starts_for_each_pattern?.should be_true
  end

  it "merges dense config overrides without sharing the quit set" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["base"]
    ).not_nil!
    override_prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["override"]
    ).not_nil!
    base = Regex::Automata::DFA::DFA.config
      .accelerate(false)
      .prefilter(prefilter)
      .match_kind(Regex::Automata::MatchKind::All)
      .quit('x'.ord.to_u8, true)
      .dfa_size_limit(123_i64)
    merged = base.overwrite(
      Regex::Automata::DFA::DFA.config
        .accelerate(true)
        .prefilter(override_prefilter)
        .start_kind(Regex::Automata::StartKind::Anchored)
        .determinize_size_limit(456_i64)
    )

    merged.get_accelerate.should be_true
    merged.get_prefilter.should be(override_prefilter)
    merged.get_match_kind.should eq(Regex::Automata::MatchKind::All)
    merged.get_starts.should eq(Regex::Automata::StartKind::Anchored)
    merged.get_quit('x'.ord.to_u8).should be_true
    merged.get_dfa_size_limit.should eq(123_i64)
    merged.get_determinize_size_limit.should eq(456_i64)

    base.quit('y'.ord.to_u8, true)
    merged.get_quit('y'.ord.to_u8).should be_false
  end

  it "honors quit bytes with caller-supplied byte classes" do
    nfa = Regex::Automata::NFA::NFA.new("abc")
    config = Regex::Automata::DFA::DFA.config.quit('x'.ord.to_u8, true)
    dfa = Regex::Automata::DFA::Builder.new(
      config,
      nfa,
      nil,
      Regex::Automata::ByteClasses.identity
    ).build

    result = dfa.try_search_fwd(Regex::Automata::Input.new("abx"))
    result.should be_a(Regex::Automata::MatchError)
    result.as(Regex::Automata::MatchError).quit?.should be_true
  end

  it "exposes builder and config convenience constructors" do
    dfa = Regex::Automata::DFA::DFA.builder
      .configure(Regex::Automata::DFA::DFA.config.start_kind(Regex::Automata::StartKind::Anchored))
      .build("abc")

    dfa.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::No))
      .should be_a(Regex::Automata::UnsupportedAnchoredStartError)
  end

  it "merges successive dense builder configurations" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.byte_classes(false))
      .configure(Regex::Automata::DFA::DFA.config.start_kind(Regex::Automata::StartKind::Anchored))
      .build("abc")

    dfa.byte_classifier.is_singleton.should be_true
    dfa.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::No))
      .should be_a(Regex::Automata::UnsupportedAnchoredStartError)
  end

  it "preserves successive Thompson builder configurations" do
    dfa = Regex::Automata::DFA::Builder.new
      .thompson { |config| config.reverse(true) }
      .thompson { |config| config.utf8(false) }
      .syntax { |config| config.unicode(false).utf8(false) }
      .build("(?-u:[\\xFF])")

    dfa.try_search_rev(Regex::Automata::Input.new(Bytes[0xFF_u8])).should eq(
      Regex::Automata::HalfMatch.must(0, 0)
    )
  end

  it "builds dense DFAs through convenience constructors" do
    dfa = Regex::Automata::DFA::DFA.new("abc")
    dfa.try_search_fwd(Regex::Automata::Input.new("zabc")).should eq(
      Regex::Automata::HalfMatch.must(0, 4)
    )

    many = Regex::Automata::DFA::DFA.new_many(["abc", "def"])
    many.pattern_len.should eq(2)
    many.try_search_fwd(Regex::Automata::Input.new("def")).should eq(
      Regex::Automata::HalfMatch.must(1, 3)
    )
  end

  it "builds a dense DFA from a precompiled NFA" do
    hir = Regex::Syntax.parse("ab?")
    nfa = Regex::Automata::HirCompiler.new.compile(hir)
    dfa = Regex::Automata::DFA::Builder.from_nfa(nfa).build

    dfa.try_search_fwd(Regex::Automata::Input.new("ab")).should eq(
      Regex::Automata::HalfMatch.must(0, 2)
    )
    dfa.try_search_fwd(Regex::Automata::Input.new("a")).should eq(
      Regex::Automata::HalfMatch.must(0, 1)
    )
  end

  it "keeps builder workflows isolated across configure and thompson variants" do
    base = Regex::Automata::DFA::Builder.new
    anchored = base.configure(Regex::Automata::DFA::DFA.config.start_kind(Regex::Automata::StartKind::Anchored))
    reversed = base.thompson { |config| config.reverse(true) }

    base.build("abc").try_search_fwd(Regex::Automata::Input.new("zabc")).should eq(
      Regex::Automata::HalfMatch.must(0, 4)
    )

    anchored.build("abc")
      .start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::No))
      .should be_a(Regex::Automata::UnsupportedAnchoredStartError)

    reversed.build("ab?").try_search_rev(Regex::Automata::Input.new("ab")).should eq(
      Regex::Automata::HalfMatch.must(0, 0)
    )
  end

  it "honors syntax configuration before HIR compilation" do
    dfa = Regex::Automata::DFA::Builder.new
      .syntax { |config| config.unicode(false).utf8(false) }
      .build("(?-u:[\\xFF])")

    dfa.try_search_fwd(Regex::Automata::Input.new(Bytes[0xFF_u8])).should eq(
      Regex::Automata::HalfMatch.must(0, 1)
    )
  end

  it "attaches prefilters through config and the DFA setter" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["abc"]
    ).not_nil!
    dfa = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.prefilter(prefilter))
      .build("abc")

    dfa.get_prefilter.should be(prefilter)
    dfa.flags.has_prefilter.should be_true
    dfa.as_ref.should be(dfa)
    dfa.to_owned.should be(dfa)

    dfa.set_prefilter(nil)
    dfa.get_prefilter.should be_nil
    dfa.flags.has_prefilter.should be_false
  end

  it "preserves a pending leftmost match when a prefilter finds a later candidate" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["ab", "c"]
    ).not_nil!
    dfa = Regex::Automata::DFA::Builder.new
      .configure(
        Regex::Automata::DFA::DFA.config
          .prefilter(prefilter)
          .starts_for_each_pattern(true)
      )
      .build("(?:ab|c)*c")
    input = Regex::Automata::Input.new("cabac")
    expected = Regex::Automata::HalfMatch.must(0, 1)

    dfa.try_search_fwd(input).should eq(expected)
    dfa.to_sparse.try_search_fwd(input).should eq(expected)
  end

  it "restarts context-sensitive DFA searches at prefilter candidates" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["abc"]
    ).not_nil!
    dfa = Regex::Automata::DFA::Builder.new
      .configure(
        Regex::Automata::DFA::DFA.config
          .prefilter(prefilter)
          .specialize_start_states(true)
      )
      .build("(?-u:\\b)abc")
    input = Regex::Automata::Input.new("xabc ").span(1...4)

    # Restarting at offset 1 must retain the preceding `x`; otherwise the
    # artificial beginning of the candidate span would incorrectly satisfy
    # the word boundary.
    dfa.try_search_fwd(input).should be_nil
    state = Regex::Automata::OverlappingState.new
    dfa.try_search_overlapping_fwd(input, state).should be_nil
    state.get_match.should be_nil
  end

  it "reports DFA size-limit failures through BuildError" do
    error = expect_raises(Regex::Automata::BuildError) do
      Regex::Automata::DFA::Builder.new
        .configure(Regex::Automata::DFA::DFA.config.dfa_size_limit(1_i64))
        .build("abc")
    end

    error.is_size_limit_exceeded.should be_true
  end

  it "distinguishes dense size-limit failures from unsupported syntax" do
    size_error = expect_raises(Regex::Automata::BuildError) do
      Regex::Automata::DFA::Builder.new
        .configure(Regex::Automata::DFA::DFA.config.dfa_size_limit(1_i64))
        .build("abc")
    end
    size_error.is_size_limit_exceeded.should be_true

    unsupported_error = expect_raises(Regex::Automata::BuildError) do
      Regex::Automata::DFA::Builder.new.build("\\babc\\b")
    end
    unsupported_error.is_size_limit_exceeded.should be_false
  end

  it "reports determinization scratch-limit failures through BuildError" do
    error = expect_raises(Regex::Automata::BuildError) do
      Regex::Automata::DFA::Builder.new
        .configure(Regex::Automata::DFA::DFA.config.determinize_size_limit(1_i64))
        .build("abc")
    end

    error.is_size_limit_exceeded.should be_true
  end

  it "minimizes dense DFAs when requested" do
    unminimized = Regex::Automata::DFA::Builder.new
      .build("(foo|boo|zoo)")
    minimized = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.minimize(true))
      .build("(foo|boo|zoo)")

    minimized.size.should be < unminimized.size
    minimized.try_search_fwd(Regex::Automata::Input.new("boo")).should eq(
      Regex::Automata::HalfMatch.must(0, 3)
    )
    minimized.try_search_fwd(Regex::Automata::Input.new("zoo")).should eq(
      Regex::Automata::HalfMatch.must(0, 3)
    )
  end

  it "preserves EOI and per-pattern start IDs through minimization and serialization" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure(
        Regex::Automata::DFA::DFA.config
          .minimize(true)
          .starts_for_each_pattern(true)
          .specialize_start_states(true)
      )
      .build_many(["foo$", "bar", "(?-u:\\b)baz"])
    roundtrip = Regex::Automata::DFA::DFA.from_bytes(dfa.to_bytes_native_endian[0])[0]

    [dfa, roundtrip].each do |candidate|
      candidate.try_search_fwd(Regex::Automata::Input.new("foo")).should eq(
        Regex::Automata::HalfMatch.must(0, 3)
      )
      candidate.try_search_fwd(Regex::Automata::Input.new("bar")).should eq(
        Regex::Automata::HalfMatch.must(1, 3)
      )
      input = Regex::Automata::Input.new("baz")
        .anchored_pattern(Regex::Automata::PatternID.new(2))
      candidate.try_search_fwd(input).should eq(Regex::Automata::HalfMatch.must(2, 3))
      candidate.to_sparse.try_search_fwd(Regex::Automata::Input.new("foo")).should eq(
        Regex::Automata::HalfMatch.must(0, 3)
      )
    end
  end

  it "rejects unicode word boundaries unless heuristic support is enabled" do
    expect_raises(Regex::Automata::BuildError) do
      Regex::Automata::DFA::DFA.builder.build("\\bxyz\\b")
    end

    Regex::Automata::DFA::DFA.builder.build("(?-u:\\b)xyz(?-u:\\b)").should be_a(Regex::Automata::DFA::DFA)
  end

  it "round-trips a never-match DFA" do
    dfa = Regex::Automata::DFA::DFA.never_match
    bytes = dfa.to_bytes_native_endian[0]
    roundtrip = Regex::Automata::DFA::DFA.from_bytes(bytes)[0]

    roundtrip.try_search_fwd(Regex::Automata::Input.new("foo12345")).should be_nil
  end

  it "round-trips an always-match DFA" do
    dfa = Regex::Automata::DFA::DFA.always_match
    bytes = dfa.to_bytes_native_endian[0]
    roundtrip = Regex::Automata::DFA::DFA.from_bytes(bytes)[0]

    roundtrip.try_search_fwd(Regex::Automata::Input.new("foo12345")).should eq(
      Regex::Automata::HalfMatch.must(0, 0)
    )
  end

  it "quits on non-ascii bytes for reverse heuristic unicode boundaries" do
    dfa = Regex::Automata::DFA::DFA.builder
      .configure(Regex::Automata::DFA::DFA.config.unicode_word_boundary(true))
      .thompson { |config| config.reverse(true) }
      .build("\\b[0-9]+\\b")

    result = dfa.try_search_rev(Regex::Automata::Input.new("β123").range(2...5))
    result.should be_a(Regex::Automata::MatchError)
    error = result.as(Regex::Automata::MatchError)
    error.quit?.should be_true
    error.byte.should eq(0xB2_u8)
    error.offset.should eq(1)

    result = dfa.try_search_rev(Regex::Automata::Input.new("123β").range(0...3))
    result.should be_a(Regex::Automata::MatchError)
    error = result.as(Regex::Automata::MatchError)
    error.quit?.should be_true
    error.byte.should eq(0xCE_u8)
    error.offset.should eq(3)
  end

  it "reports dense metadata derived from the transition table" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure { |config| config.starts_for_each_pattern(true) }
      .build_many(["abc", "(?-u:\\b)def", "ghi$"])

    dfa.alphabet_len.should eq(dfa.byte_classifier.alphabet_len)
    dfa.stride.should eq(1 << dfa.stride2)
    dfa.stride.should be >= dfa.alphabet_len
    dfa.memory_usage.should eq(dfa.to_bytes_native_endian[0].size)
  end

  it "round-trips dense state indexes through premultiplied IDs" do
    dfa = Regex::Automata::DFA::Builder.new.build("(?:foo|bar|baz)[0-9]+")

    dfa.state_len.should eq(dfa.size)
    dfa.state_len.times do |index|
      id = dfa.to_state_id(index)
      dfa.to_index(id).should eq(index)
      dfa[id].id.should eq(id)
    end
  end

  it "keeps transition and start IDs coherent after state partitioning" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure { |config| config.starts_for_each_pattern(true).specialize_start_states(true) }
      .build_many(["a[^x]*x", "(?-u:\\b)foo", "bar$"])

    dfa.states.each_index do |index|
      id = dfa.to_state_id(index)
      (dfa.alphabet_len - 1).times do |byte_class|
        next_id = dfa.tt.not_nil!.next_state_by_class(id, byte_class)
        dfa.to_index(next_id).should be >= 0
        dfa.to_index(next_id).should be < dfa.state_len
      end
      eoi_id = dfa.next_eoi_state(id)
      dfa.to_index(eoi_id).should be >= 0
      dfa.to_index(eoi_id).should be < dfa.state_len
    end

    %w[aZZx foo bar].each do |haystack|
      dfa.try_search_fwd(haystack.to_slice).should_not be_a(Regex::Automata::MatchError)
    end
  end

  it "round-trips little, big, and native-endian dense bytes" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure { |config| config.starts_for_each_pattern(true) }
      .build_many(["foo[0-9]+", "bar[0-9]+"])

    {dfa.to_bytes_little_endian, dfa.to_bytes_big_endian, dfa.to_bytes_native_endian}.each do |serialized|
      bytes, written = serialized
      roundtrip, read = Regex::Automata::DFA::DFA.from_bytes(bytes)

      read.should eq(written)
      roundtrip.try_search_fwd(Regex::Automata::Input.new("foo123")).should eq(
        Regex::Automata::HalfMatch.must(0, 6)
      )
      roundtrip.try_search_fwd(Regex::Automata::Input.new("bar456")).should eq(
        Regex::Automata::HalfMatch.must(1, 6)
      )
    end
  end

  it "writes dense bytes into caller-provided buffers" do
    dfa = Regex::Automata::DFA::DFA.new("abc")

    little_bytes, little_written = dfa.to_bytes_little_endian
    big_bytes, big_written = dfa.to_bytes_big_endian
    native_bytes, native_written = dfa.to_bytes_native_endian

    dfa.write_to_len.should eq(native_written)

    little_dst = Bytes.new(little_written)
    big_dst = Bytes.new(big_written)
    native_dst = Bytes.new(native_written)

    dfa.write_to_little_endian(little_dst).should eq(little_written)
    dfa.write_to_big_endian(big_dst).should eq(big_written)
    dfa.write_to_native_endian(native_dst).should eq(native_written)

    little_dst.should eq(little_bytes)
    big_dst.should eq(big_bytes)
    native_dst.should eq(native_bytes)

    too_small = Bytes.new(native_written - 1)
    expect_raises(Regex::Automata::SerializeError) do
      dfa.write_to_native_endian(too_small)
    end
  end

  it "validates serialized start states before computing universal starts" do
    dfa = Regex::Automata::DFA::DFA.new("abc")
    bytes = dfa.to_bytes_little_endian[0].dup
    invalid_start = ((dfa.size + 10) << dfa.stride2).to_u32

    write_u32_le(bytes, 28, invalid_start)

    expect_raises(Regex::Automata::DeserializeError) do
      Regex::Automata::DFA::DFA.from_bytes(bytes)
    end
  end

  it "rejects serialized start states that point to a match state" do
    dfa = Regex::Automata::DFA::DFA.new("abc")
    bytes = dfa.to_bytes_little_endian[0].dup
    match_id = dfa.states.find(&.accepting?).not_nil!.id.to_i.to_u32

    # The format writes the two compatibility starts followed by six
    # unanchored and six anchored start-table entries.
    (20...76).step(4) { |offset| write_u32_le(bytes, offset, match_id) }

    error = expect_raises(Regex::Automata::DeserializeError) do
      Regex::Automata::DFA::DFA.from_bytes(bytes)
    end
    error.message.not_nil!.should contain("start states cannot be match states")
  end
end
