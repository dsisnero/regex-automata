require "./spec_helper"

describe Regex::Automata::Wire do
  it "round trips aligned serialization labels" do
    buffer = Bytes.new(1024, 0_u8)
    written = Regex::Automata::Wire.write_label("fooba", buffer)

    written.should eq(8)
    buffer[0, written].should eq("fooba\0\0\0".to_slice)
    Regex::Automata::Wire.read_label(buffer, "fooba").should eq(8)
  end

  it "rejects invalid serialization labels" do
    buffer = Bytes.new(1024, 0_u8)
    Regex::Automata::Wire.write_label("z" * 255, buffer).should be > 0

    expect_raises(ArgumentError, /NUL/) do
      Regex::Automata::Wire.write_label("foo\0bar", buffer)
    end
    expect_raises(ArgumentError, /255/) do
      Regex::Automata::Wire.write_label("z" * 256, buffer)
    end
  end

  it "uses four-byte wire padding" do
    [0, 3, 2, 1, 0, 3, 2, 1, 0].each_with_index do |expected, index|
      Regex::Automata::Wire.padding_len(8 + index).should eq(expected)
    end
  end

  it "uses vendored serialization error text" do
    Regex::Automata::SerializeError.buffer_too_small("bytes").message.should eq("destination buffer is too small to write bytes")
    Regex::Automata::DeserializeError.buffer_too_small("bytes").message.should eq("buffer is too small to read bytes")
    Regex::Automata::DeserializeError.invalid_usize("offset").message.should eq("offset is too big to fit in a usize")
    Regex::Automata::DeserializeError.version_mismatch(1_u32, 2_u32).message.should eq("unsupported version: expected version 1 but found version 2")
    Regex::Automata::DeserializeError.endian_mismatch(0xAB_u32, 0xCD_u32).message.not_nil!.should contain("expected 0xAB but got 0xCD")
    Regex::Automata::DeserializeError.alignment_mismatch(4, 0x123_u64).message.not_nil!.should contain("address 0x123")
    Regex::Automata::DeserializeError.arithmetic_overflow("state count").message.should eq("arithmetic overflow for state count")

    small_error = Regex::Automata::SmallIndexError.new(Int32::MAX.to_i64)
    pattern_error = Regex::Automata::PatternIDError.new(small_error)
    state_error = Regex::Automata::StateIDError.new(small_error)
    Regex::Automata::DeserializeError.pattern_id_error(pattern_error, "match map").message.should eq("failed to read pattern ID for match map: #{pattern_error}")
    Regex::Automata::DeserializeError.state_id_error(state_error, "transition").message.should eq("failed to read state ID for transition: #{state_error}")
  end
end
