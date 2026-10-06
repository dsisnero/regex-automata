require "./spec_helper"

describe "primitive identifier helpers" do
  it "builds and round-trips small indices" do
    small = Regex::Automata::SmallIndex.new(7)
    small.should be_a(Regex::Automata::SmallIndex)

    index = small.as(Regex::Automata::SmallIndex)
    index.to_i.should eq(7)
    index.as_i32.should eq(7)
    index.as_u32.should eq(7_u32)
    index.as_u64.should eq(7_u64)
    index.as_usize.should eq(7)
    index.one_more.should eq(8)
    index.to_ne_bytes.size.should eq(4)

    decoded = Regex::Automata::SmallIndex.from_ne_bytes(index.to_ne_bytes)
    decoded.should eq(index)
  end

  it "reports attempted values for invalid decoded small indices" do
    bytes = Bytes.new(4)
    IO::Memory.new(bytes).write_bytes(Int32::MAX.to_u32, IO::ByteFormat::SystemEndian)
    result = Regex::Automata::SmallIndex.from_ne_bytes(bytes)

    result.should be_a(Regex::Automata::SmallIndexError)
    result.as(Regex::Automata::SmallIndexError).attempted.should eq(Int32::MAX.to_i64)
    result.to_s.should contain("failed to create small index")
  end

  it "preserves non-max usize semantics" do
    Regex::Automata::NonMaxUsize.new(4).not_nil!.get.should eq(4)
  end

  it "provides pattern and state identifier compatibility helpers" do
    Regex::Automata::PatternID::ZERO.to_i.should eq(0)
    Regex::Automata::StateID::ZERO.to_i.should eq(0)
    Regex::Automata::PatternID::SIZE.should eq(4)
    Regex::Automata::StateID::SIZE.should eq(4)

    pid = Regex::Automata::PatternID.must(9)
    sid = Regex::Automata::StateID.must(11)

    pid.one_more.should eq(10)
    sid.one_more.should eq(12)
    pid.as_i32.should eq(9)
    pid.as_u64.should eq(9_u64)
    sid.as_usize.should eq(11)

    Regex::Automata::PatternID.from_ne_bytes(pid.to_ne_bytes).should eq(pid)
    Regex::Automata::StateID.from_ne_bytes(sid.to_ne_bytes).should eq(sid)
  end

  it "uses identifier-specific errors for invalid decoded identifiers" do
    bytes = Bytes.new(4)
    IO::Memory.new(bytes).write_bytes(Int32::MAX.to_u32, IO::ByteFormat::SystemEndian)

    pid_error = Regex::Automata::PatternID.from_ne_bytes(bytes)
    sid_error = Regex::Automata::StateID.from_ne_bytes(bytes)

    pid_error.should be_a(Regex::Automata::PatternIDError)
    sid_error.should be_a(Regex::Automata::StateIDError)
    pid_error.as(Regex::Automata::PatternIDError).attempted.should eq(Int32::MAX.to_i64)
    sid_error.as(Regex::Automata::StateIDError).attempted.should eq(Int32::MAX.to_i64)
  end
end
