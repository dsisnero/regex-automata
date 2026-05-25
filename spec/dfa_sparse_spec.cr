require "./spec_helper"

describe "DFA::Sparse" do
  it "builds sparse DFAs from dense conversion and default constructors" do
    dense = Regex::Automata::DFA::DFA.new("foo[0-9]+")
    sparse = dense.to_sparse

    sparse.try_search_fwd(Regex::Automata::Input.new("foo12345")).should eq(
      Regex::Automata::HalfMatch.must(0, 8)
    )

    direct = Regex::Automata::DFA::Sparse::DFA.new("foo[0-9]+")
    direct.try_search_fwd(Regex::Automata::Input.new("foo12345")).should eq(
      Regex::Automata::HalfMatch.must(0, 8)
    )
  end

  it "supports sparse always-match and never-match constructors" do
    always = Regex::Automata::DFA::Sparse::DFA.always_match
    always.try_search_fwd(Regex::Automata::Input.new("foo")).should eq(
      Regex::Automata::HalfMatch.must(0, 0)
    )

    never = Regex::Automata::DFA::Sparse::DFA.never_match
    never.try_search_fwd(Regex::Automata::Input.new("foo")).should be_nil
  end

  it "exposes sparse metadata and prefilter attachment" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["abc"]
    ).not_nil!
    sparse = Regex::Automata::DFA::Builder.new
      .configure(
        Regex::Automata::DFA::DFA.config
          .start_kind(Regex::Automata::StartKind::Anchored)
          .starts_for_each_pattern(true)
      )
      .build_many(["abc", "def"])
      .to_sparse

    sparse.start_kind.should eq(Regex::Automata::StartKind::Anchored)
    sparse.starts_for_each_pattern.should be_true
    sparse.byte_classes.alphabet_len.should eq(
      sparse.dense.byte_classifier.alphabet_len
    )

    sparse.set_prefilter(prefilter)
    sparse.get_prefilter.should be(prefilter)
    sparse.memory_usage.should eq(sparse.write_to_len)
    sparse.to_owned.try_search_fwd(
      Regex::Automata::Input.new("def").anchored(Regex::Automata::Anchored::Yes)
    ).should eq(
      Regex::Automata::HalfMatch.must(1, 3)
    )
  end

  it "round-trips sparse serialization in all endianness helpers" do
    sparse = Regex::Automata::DFA::Builder.new
      .configure { |config| config.starts_for_each_pattern(true) }
      .build_many(["foo[0-9]+", "bar[0-9]+"])
      .to_sparse

    {
      sparse.to_bytes_little_endian,
      sparse.to_bytes_big_endian,
      sparse.to_bytes_native_endian,
    }.each do |serialized|
      bytes, written = serialized
      roundtrip, read = Regex::Automata::DFA::Sparse::DFA.from_bytes(bytes)

      read.should eq(written)
      roundtrip.try_search_fwd(Regex::Automata::Input.new("foo123")).should eq(
        Regex::Automata::HalfMatch.must(0, 6)
      )
      roundtrip.try_search_fwd(Regex::Automata::Input.new("bar456")).should eq(
        Regex::Automata::HalfMatch.must(1, 6)
      )
    end
  end

  it "writes sparse bytes into caller-provided buffers" do
    sparse = Regex::Automata::DFA::Sparse::DFA.new("abc")

    little_bytes, little_written = sparse.to_bytes_little_endian
    big_bytes, big_written = sparse.to_bytes_big_endian
    native_bytes, native_written = sparse.to_bytes_native_endian

    sparse.write_to_len.should eq(native_written)

    little_dst = Bytes.new(little_written)
    big_dst = Bytes.new(big_written)
    native_dst = Bytes.new(native_written)

    sparse.write_to_little_endian(little_dst).should eq(little_written)
    sparse.write_to_big_endian(big_dst).should eq(big_written)
    sparse.write_to_native_endian(native_dst).should eq(native_written)

    little_dst.should eq(little_bytes)
    big_dst.should eq(big_bytes)
    native_dst.should eq(native_bytes)

    expect_raises(Regex::Automata::SerializeError) do
      sparse.write_to_native_endian(Bytes.new(native_written - 1))
    end
  end

  it "quits on non-ascii bytes for sparse forward heuristic unicode boundaries" do
    sparse = Regex::Automata::DFA::DFA.builder
      .configure(Regex::Automata::DFA::DFA.config.unicode_word_boundary(true))
      .thompson { |config| config.reverse(true) }
      .build("\\b[0-9]+\\b")
      .to_sparse

    result = sparse.try_search_fwd(Regex::Automata::Input.new("β123").range(2...5))
    result.should be_a(Regex::Automata::MatchError)
    error = result.as(Regex::Automata::MatchError)
    error.quit?.should be_true
    error.byte.should eq(0xB2_u8)
    error.offset.should eq(1)

    result = sparse.try_search_fwd(Regex::Automata::Input.new("123β").range(0...3))
    result.should be_a(Regex::Automata::MatchError)
    error = result.as(Regex::Automata::MatchError)
    error.quit?.should be_true
    error.byte.should eq(0xCE_u8)
    error.offset.should eq(3)
  end

  it "quits on non-ascii bytes for sparse reverse heuristic unicode boundaries" do
    sparse = Regex::Automata::DFA::DFA.builder
      .configure(Regex::Automata::DFA::DFA.config.unicode_word_boundary(true))
      .thompson { |config| config.reverse(true) }
      .build("\\b[0-9]+\\b")
      .to_sparse

    result = sparse.try_search_rev(Regex::Automata::Input.new("β123").range(2...5))
    result.should be_a(Regex::Automata::MatchError)
    error = result.as(Regex::Automata::MatchError)
    error.quit?.should be_true
    error.byte.should eq(0xB2_u8)
    error.offset.should eq(1)

    result = sparse.try_search_rev(Regex::Automata::Input.new("123β").range(0...3))
    result.should be_a(Regex::Automata::MatchError)
    error = result.as(Regex::Automata::MatchError)
    error.quit?.should be_true
    error.byte.should eq(0xCE_u8)
    error.offset.should eq(3)
  end
end
