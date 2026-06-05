require "./spec_helper"

private def write_u32_le(bytes : Bytes, offset : Int32, value : UInt32) : Nil
  bytes[offset] = (value & 0xFF).to_u8
  bytes[offset + 1] = ((value >> 8) & 0xFF).to_u8
  bytes[offset + 2] = ((value >> 16) & 0xFF).to_u8
  bytes[offset + 3] = ((value >> 24) & 0xFF).to_u8
end

describe "DFA::Dense" do
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

  it "exposes builder and config convenience constructors" do
    dfa = Regex::Automata::DFA::DFA.builder
      .configure(Regex::Automata::DFA::DFA.config.start_kind(Regex::Automata::StartKind::Anchored))
      .build("abc")

    dfa.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::No))
      .should be_a(Regex::Automata::UnsupportedAnchoredStartError)
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

  it "reports DFA size-limit failures through BuildError" do
    error = expect_raises(Regex::Automata::BuildError) do
      Regex::Automata::DFA::Builder.new
        .configure(Regex::Automata::DFA::DFA.config.dfa_size_limit(1_i64))
        .build("abc")
    end

    error.is_size_limit_exceeded.should be_true
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
end
