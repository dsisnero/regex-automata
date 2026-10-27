require "./spec_helper"

describe Regex::Automata::Wire do
  it "round trips aligned serialization labels" do
    buffer = Bytes.new(1024, 0_u8)
    written = Regex::Automata::Wire.write_label("fooba", buffer)

    written.should eq(8)
    buffer[0, written].should eq("fooba\0\0\0".to_slice)
    Regex::Automata::Wire.read_label(buffer, "fooba").should eq(8)
  end

  it "preserves the pinned reader's label-length calculation" do
    # wire.rs::read_label adds padding_len(first_nul), not the terminator
    # length; this boundary is observable for labels of length 4.
    Regex::Automata::Wire.read_label(Bytes[97, 98, 99, 100, 0, 0, 0, 0], "abcd").should eq(4)
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

  it "checks native-endian header fields and truncated buffers" do
    bytes = Bytes.new(4)
    IO::ByteFormat::SystemEndian.encode(0xFEFF_u32, bytes)
    Regex::Automata::Wire.read_endianness_check(bytes).should eq(4)
    Regex::Automata::Wire.try_read_u32(bytes, "endianness check").should eq({0xFEFF_u32, 4})
    expect_raises(Regex::Automata::DeserializeError, /buffer is too small to read endianness check/) do
      Regex::Automata::Wire.read_endianness_check(bytes[0, 3])
    end
    IO::ByteFormat::SystemEndian.encode(0xFFFE_u32, bytes)
    expect_raises(Regex::Automata::DeserializeError, /endianness mismatch/) do
      Regex::Automata::Wire.read_endianness_check(bytes)
    end
    IO::ByteFormat::SystemEndian.encode(5_u32, bytes)
    Regex::Automata::Wire.read_version(bytes, 5_u32).should eq(4)
    expect_raises(Regex::Automata::DeserializeError, /expected version 4 but found version 5/) do
      Regex::Automata::Wire.read_version(bytes, 4_u32)
    end
  end

  it "rejects invalid IDs and checks untrusted arithmetic" do
    bytes = Bytes.new(4)
    IO::ByteFormat::SystemEndian.encode(7_u32, bytes)
    Regex::Automata::Wire.try_read_state_id(bytes, "transition").should eq({Regex::Automata::StateID.must(7), 4})
    Regex::Automata::Wire.read_pattern_id(bytes, "match map").should eq({Regex::Automata::PatternID.must(7), 4})
    IO::ByteFormat::SystemEndian.encode(0xFFFF_FFFF_u32, bytes)
    expect_raises(Regex::Automata::DeserializeError, /failed to read state ID for transition/) do
      Regex::Automata::Wire.try_read_state_id(bytes, "transition")
    end
    expect_raises(Regex::Automata::DeserializeError, /buffer is too small to read transition/) do
      Regex::Automata::Wire.try_read_state_id(bytes[0, 3], "transition")
    end
    Regex::Automata::Wire.add(2_u64, 3_u64, "length").should eq(5_u64)
    Regex::Automata::Wire.mul(2_u64, 3_u64, "length").should eq(6_u64)
    Regex::Automata::Wire.shl(1_u64, 3_u64, "length").should eq(8_u64)
    # Rust checked_shl rejects an oversized shift count, not shifted-out bits.
    Regex::Automata::Wire.shl(UInt64::MAX, 1_u64, "length").should eq(UInt64::MAX - 1_u64)
    expect_raises(Regex::Automata::DeserializeError, /arithmetic overflow for length/) do
      Regex::Automata::Wire.add(UInt64::MAX, 1_u64, "length")
    end
    expect_raises(Regex::Automata::DeserializeError, /arithmetic overflow for length/) do
      Regex::Automata::Wire.mul(UInt64::MAX, 2_u64, "length")
    end
    expect_raises(Regex::Automata::DeserializeError, /arithmetic overflow for length/) do
      Regex::Automata::Wire.shl(1_u64, 64_u64, "length")
    end
  end

  it "writes Rust header fields and IDs in both byte orders" do
    bytes = Bytes.new(4, 0_u8)
    Regex::Automata::Wire.write_endianness_check(bytes, :little).should eq(4)
    bytes.should eq(Bytes[0xFF, 0xFE, 0, 0])
    Regex::Automata::Wire.write_endianness_check(bytes, :big).should eq(4)
    bytes.should eq(Bytes[0, 0, 0xFE, 0xFF])
    Regex::Automata::Wire.write_version(0x01020304_u32, bytes, :big).should eq(4)
    bytes.should eq(Bytes[1, 2, 3, 4])
    Regex::Automata::Wire.write_pattern_id(Regex::Automata::PatternID.must(0x01020304), bytes, :little).should eq(4)
    bytes.should eq(Bytes[4, 3, 2, 1])
    expect_raises(Regex::Automata::SerializeError, /destination buffer is too small to write version number/) do
      Regex::Automata::Wire.write_version(1_u32, bytes[0, 3], :little)
    end
    # Rust's raw ID/Endian writers require sufficient space and panic on a
    # short destination; only the header wrappers return SerializeError.
    expect_raises(IndexError) do
      Regex::Automata::Wire.write_state_id(Regex::Automata::StateID.must(1), bytes[0, 3], :little)
    end
    Regex::Automata::Wire.write_endianness_check_len.should eq(4)
    Regex::Automata::Wire.write_version_len.should eq(4)
    Regex::Automata::Wire.write_u16(0x0102_u16, bytes, :big).should eq(2)
    bytes[0, 2].should eq(Bytes[1, 2])
    wide = Bytes.new(16)
    Regex::Automata::Wire.write_u128(0x0102030405060708090A0B0C0D0E0F10_u128, wide, :big).should eq(16)
    wide.should eq(Bytes[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
    Regex::Automata::Wire.write_u128(0x0102030405060708090A0B0C0D0E0F10_u128, wide, :native)
    Regex::Automata::Wire.try_read_u128(wide, "wide").should eq({0x0102030405060708090A0B0C0D0E0F10_u128, 16})
    expect_raises(Regex::Automata::DeserializeError, /buffer is too small to read wide/) do
      Regex::Automata::Wire.try_read_u128(wide[0, 15], "wide")
    end
  end

  it "uses vendor's bounded initial padding and aligned byte storage" do
    Regex::Automata::Wire.skip_initial_padding(Bytes.new(12, 0_u8)).should eq(7)
    Regex::Automata::Wire.skip_initial_padding(Bytes[0, 0, 65, 0]).should eq(2)
    buffer, padding = Regex::Automata::Wire.alloc_aligned_buffer(5, 8)
    buffer.size.should eq(5 + padding)
    padding.should be <= 7
    Regex::Automata::Wire.check_alignment(buffer[padding, 5], 8)
    if padding < 7
      expect_raises(Regex::Automata::DeserializeError, /alignment mismatch/) do
        Regex::Automata::Wire.check_alignment(buffer[padding + 1, 4], 8)
      end
    end
  end
end
