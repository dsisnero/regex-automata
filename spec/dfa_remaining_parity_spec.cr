require "./spec_helper"

private DFA_SUITE_PATTERNS = [
  "(?-u:\\b)[a-zA-Z]+(?-u:\\b)",
  "(?m)^\\S+$",
  "(?Rm)^\\S+$",
] of String

private DFA_MULTI_PATTERN_V2_PATTERNS = [
  "\\b[a-zA-Z]+\\b",
  "(?m)^\\S+$",
  "(?Rm)^\\S+$",
] of String

private def assert_suite_behavior(re : Regex::Automata::DFA::Regex) : Nil
  re.is_match("abcd").should be_true
  re.is_match(" \n").should be_false

  re.find("abcd").should eq(Regex::Automata::Match.must(0, 0...4))
  re.find("@ abcd @").should eq(Regex::Automata::Match.must(0, 2...6))
  re.find("@abcd@").should eq(Regex::Automata::Match.must(1, 0...6))
  re.find("\nabcd\n").should eq(Regex::Automata::Match.must(0, 1...5))
  re.find("\nabcd wxyz\n").should eq(Regex::Automata::Match.must(0, 1...5))
  re.find("\n@abcd@\n").should eq(Regex::Automata::Match.must(1, 1...7))
  re.find("@abcd@\r\n").should eq(Regex::Automata::Match.must(2, 0...6))
  re.find("\r\n@abcd@").should eq(Regex::Automata::Match.must(1, 2...8))
  re.find("\r\n@abcd@\r\n").should eq(Regex::Automata::Match.must(2, 2...8))
end

private def assert_multi_pattern_v2_behavior(re : Regex::Automata::DFA::Regex) : Nil
  re.is_match("abcd").should be_true
  invalid = Bytes[
    0xFF_u8,
    '@'.ord.to_u8,
    'a'.ord.to_u8,
    'b'.ord.to_u8,
    'c'.ord.to_u8,
    'd'.ord.to_u8,
    '@'.ord.to_u8,
    0xFF_u8,
  ]
  re.try_search(Regex::Automata::Input.new(invalid))
    .should be_a(Regex::Automata::MatchError)

  assert_suite_behavior(re)
end

private def build_suite_regex(builder : Regex::Automata::DFA::RegexBuilder) : Regex::Automata::DFA::Regex
  builder.build_many(DFA_SUITE_PATTERNS)
end

private def build_multi_pattern_v2_regex(builder : Regex::Automata::DFA::RegexBuilder) : Regex::Automata::DFA::Regex
  builder.build_many(DFA_MULTI_PATTERN_V2_PATTERNS)
end

private def to_sparse_regex(re : Regex::Automata::DFA::Regex) : Regex::Automata::DFA::Regex
  Regex::Automata::DFA::Regex.builder.build_from_dfas(
    re.forward.to_sparse,
    re.reverse.to_sparse
  )
end

private def roundtrip_dense_regex(re : Regex::Automata::DFA::Regex) : Regex::Automata::DFA::Regex
  forward_bytes = re.forward.to_bytes_native_endian[0]
  reverse_bytes = re.reverse.to_bytes_native_endian[0]
  forward = Regex::Automata::DFA::DFA.from_bytes(forward_bytes)[0]
  reverse = Regex::Automata::DFA::DFA.from_bytes(reverse_bytes)[0]
  Regex::Automata::DFA::Regex.builder.build_from_dfas(forward, reverse)
end

private def roundtrip_sparse_regex(re : Regex::Automata::DFA::Regex) : Regex::Automata::DFA::Regex
  forward_sparse = re.forward.to_sparse
  reverse_sparse = re.reverse.to_sparse
  forward_bytes = forward_sparse.to_bytes_native_endian[0]
  reverse_bytes = reverse_sparse.to_bytes_native_endian[0]
  forward = Regex::Automata::DFA::Sparse::DFA.from_bytes(forward_bytes)[0]
  reverse = Regex::Automata::DFA::Sparse::DFA.from_bytes(reverse_bytes)[0]
  Regex::Automata::DFA::Regex.builder.build_from_dfas(forward, reverse)
end

private def dense_byte_class_count_offset(dfa : Regex::Automata::DFA::DFA) : Int32
  8 + 4 + 4 + 4 + 4 + 4 + (Regex::Automata::Start.len * 2 * 4) + 4 + (dfa.st.pattern_states.size * (4 + Regex::Automata::Start.len * 4))
end

private def write_u32_le_spec(bytes : Bytes, offset : Int32, value : UInt32) : Nil
  bytes[offset] = (value & 0xFF).to_u8
  bytes[offset + 1] = ((value >> 8) & 0xFF).to_u8
  bytes[offset + 2] = ((value >> 16) & 0xFF).to_u8
  bytes[offset + 3] = ((value >> 24) & 0xFF).to_u8
end

describe "DFA remaining parity" do
  it "ports minimize_sets_correct_match_states" do
    pattern = <<-'REGEX'
(?x)
    (?:
        \p{gcb=Prepend}*
        (?:
            (?:
                (?:
                    \p{gcb=L}*
                    (?:\p{gcb=V}+|\p{gcb=LV}\p{gcb=V}*|\p{gcb=LVT})
                    \p{gcb=T}*
                )
                |
                \p{gcb=L}+
                |
                \p{gcb=T}+
            )
            |
            \p{Extended_Pictographic}
            (?:\p{gcb=Extend}*\p{gcb=ZWJ}\p{Extended_Pictographic})*
            |
            [^\p{gcb=Control}\p{gcb=CR}\p{gcb=LF}]
        )
        [\p{gcb=Extend}\p{gcb=ZWJ}\p{gcb=SpacingMark}]*
    )
REGEX

    dfa = Regex::Automata::DFA::DFA.builder
      .configure(
        Regex::Automata::DFA::DFA.config
          .start_kind(Regex::Automata::StartKind::Anchored)
          .minimize(true)
      )
      .build(pattern)

    input = Regex::Automata::Input.new(Bytes[0xE2_u8])
      .anchored(Regex::Automata::Anchored::Yes)
    dfa.try_search_fwd(input).should be_nil
  end

  it "ports unminimized_default" do
    assert_suite_behavior(
      build_suite_regex(Regex::Automata::DFA::Regex.builder)
    )
  end

  it "ports unminimized_prefilter" do
    prefilter = Regex::Automata::Prefilter
      .new(Regex::Automata::MatchKind::LeftmostFirst, ["abcd"])
      .not_nil!
    builder = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.prefilter(prefilter))

    assert_suite_behavior(build_suite_regex(builder))
  end

  it "ports unminimized_specialized_start_states" do
    builder = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.specialize_start_states(true))

    assert_suite_behavior(build_suite_regex(builder))
  end

  it "ports unminimized_no_byte_class" do
    builder = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.byte_classes(false))

    assert_suite_behavior(build_suite_regex(builder))
  end

  it "ports unminimized_nfa_shrink" do
    builder = Regex::Automata::DFA::Regex.builder
      .thompson { |config| config.shrink(true) }

    assert_suite_behavior(build_suite_regex(builder))
  end

  it "ports minimized_default" do
    builder = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.minimize(true))

    assert_suite_behavior(build_suite_regex(builder))
  end

  it "ports minimized_no_byte_class" do
    builder = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.minimize(true).byte_classes(false))

    assert_suite_behavior(build_suite_regex(builder))
  end

  it "ports sparse_unminimized_default" do
    assert_suite_behavior(
      to_sparse_regex(build_suite_regex(Regex::Automata::DFA::Regex.builder))
    )
  end

  it "ports sparse_unminimized_prefilter" do
    prefilter = Regex::Automata::Prefilter
      .new(Regex::Automata::MatchKind::LeftmostFirst, ["abcd"])
      .not_nil!
    builder = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.prefilter(prefilter))

    assert_suite_behavior(
      to_sparse_regex(build_suite_regex(builder))
    )
  end

  it "ports serialization_unminimized_default" do
    re = build_suite_regex(Regex::Automata::DFA::Regex.builder)
    assert_suite_behavior(roundtrip_dense_regex(re))
  end

  it "ports sparse_serialization_unminimized_default" do
    re = build_suite_regex(Regex::Automata::DFA::Regex.builder)
    assert_suite_behavior(roundtrip_sparse_regex(re))
  end

  it "ports multi_pattern_v2 for dense generated fixtures via port-native serialization" do
    builder = Regex::Automata::DFA::Regex.builder
      .dense(
        Regex::Automata::DFA::DFA.config
          .starts_for_each_pattern(true)
          .specialize_start_states(true)
          .start_kind(Regex::Automata::StartKind::Both)
          .unicode_word_boundary(true)
          .minimize(true)
      )

    re = build_multi_pattern_v2_regex(builder)
    assert_multi_pattern_v2_behavior(roundtrip_dense_regex(re))
  end

  it "ports multi_pattern_v2 for sparse generated fixtures via port-native serialization" do
    builder = Regex::Automata::DFA::Regex.builder
      .dense(
        Regex::Automata::DFA::DFA.config
          .starts_for_each_pattern(true)
          .specialize_start_states(true)
          .start_kind(Regex::Automata::StartKind::Both)
          .unicode_word_boundary(true)
          .minimize(true)
      )

    re = build_multi_pattern_v2_regex(builder)
    assert_multi_pattern_v2_behavior(roundtrip_sparse_regex(re))
  end

  it "ports invalid_byte_classes" do
    dfa = Regex::Automata::DFA::DFA.new("abc")
    bytes = dfa.to_bytes_little_endian[0]
    corrupted = bytes.dup
    offset = dense_byte_class_count_offset(dfa)

    write_u32_le_spec(corrupted, offset, 1_u32)

    expect_raises(Regex::Automata::DeserializeError) do
      Regex::Automata::DFA::DFA.from_bytes(corrupted)
    end
  end

  it "ports invalid_byte_classes_min" do
    dfa = Regex::Automata::DFA::DFA.builder
      .configure(Regex::Automata::DFA::DFA.config.minimize(true))
      .build("(foo|bar|baz)")
    bytes = dfa.to_bytes_little_endian[0]
    corrupted = bytes.dup
    offset = dense_byte_class_count_offset(dfa)

    write_u32_le_spec(corrupted, offset, 1_u32)

    expect_raises(Regex::Automata::DeserializeError) do
      Regex::Automata::DFA::DFA.from_bytes(corrupted)
    end
  end
end
