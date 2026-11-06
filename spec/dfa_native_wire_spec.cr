require "./spec_helper"

# Exact assertions from tests/gen/dense/mod.rs at the pinned upstream commit.
describe "Rust dense DFA wire compatibility" do
  it "loads the checked-in multi_pattern_v2 forward and reverse DFAs" do
    endian = IO::ByteFormat::SystemEndian == IO::ByteFormat::LittleEndian ? "littleendian" : "bigendian"
    base = File.join(__DIR__, "../vendor/regex/regex-automata/tests/gen/dense")
    forward_bytes = File.read(File.join(base, "multi_pattern_v2_fwd.#{endian}.dfa")).to_slice
    reverse_bytes = File.read(File.join(base, "multi_pattern_v2_rev.#{endian}.dfa")).to_slice
    forward, forward_read = Regex::Automata::DFA::DFA.from_bytes(forward_bytes)
    reverse, reverse_read = Regex::Automata::DFA::DFA.from_bytes(reverse_bytes)
    forward_read.should eq(forward_bytes.size)
    reverse_read.should eq(reverse_bytes.size)
    regex = Regex::Automata::DFA::Regex.builder.build_from_dfas(forward, reverse)
    {
      {"abcd", 0, 0, 4},
      {"@ abcd @", 0, 2, 6},
      {"@abcd@", 1, 0, 6},
      {"\nabcd\n", 0, 1, 5},
      {"\nabcd wxyz\n", 0, 1, 5},
      {"\n@abcd@\n", 1, 1, 7},
      {"@abcd@\r\n", 2, 0, 6},
      {"\r\n@abcd@", 1, 2, 8},
      {"\r\n@abcd@\r\n", 2, 2, 8},
    }.each do |haystack, pattern, start, finish|
      regex.find(haystack).should eq(Regex::Automata::Match.must(pattern, start, finish))
    end
    regex.try_search(Regex::Automata::Input.new(Bytes[0xFF, 0x40, 0x61, 0x62, 0x63, 0x64, 0x40, 0xFF])).should be_a(Regex::Automata::MatchError)
  end
end

# Source-characterization boundaries for dense.rs::from_bytes and its component
# validation, plus the exact two fuzz payloads in tests/fuzz/dense.rs.
describe "Rust dense native wire boundaries" do
  it "writes both endiannesses byte-for-byte like the checked-in Rust fixtures" do
    base = File.join(__DIR__, "../vendor/regex/regex-automata/tests/gen/dense")
    %w(fwd rev).each do |direction|
      native = Regex::Automata::DFA::DFA.native_wire_endian == :little ? "littleendian" : "bigendian"
      original = File.read(File.join(base, "multi_pattern_v2_#{direction}.#{native}.dfa")).to_slice
      dfa, _ = Regex::Automata::DFA::DFA.from_bytes(original)
      %w(littleendian bigendian).each do |endian|
        expected = File.read(File.join(base, "multi_pattern_v2_#{direction}.#{endian}.dfa")).to_slice.dup
        # Pinned Rust ByteSet::from_bytes reads its low bucket twice. Rust's
        # own deserialize/reserialize therefore replaces the final bucket.
        expected[-16, 16].copy_from(expected[-32, 16])
        actual = endian == "littleendian" ? dfa.to_bytes_little_endian[0] : dfa.to_bytes_big_endian[0]
        actual.should eq(expected)
      end
    end
  end

  %w(
    deserialize_dense_crash-9486fb7c8a93b12c12a62166b43d31640c0208a9
    deserialize_dense_minimized-from-9486fb7c8a93b12c12a62166b43d31640c0208a9
  ).each do |name|
    it "rejects the pinned fuzz input #{name} without a panic" do
      given = File.read(File.join(__DIR__, "../vendor/regex/regex-automata/tests/fuzz/testdata", name)).to_slice
      haystack_len = given[0].to_i
      payload = given[1 + haystack_len..]
      bytes = Bytes.new(40 + payload.size, 0_u8)
      Regex::Automata::Wire.write_label(Regex::Automata::DFA::DFA::WIRE_LABEL, bytes)
      Regex::Automata::Wire.write_endianness_check(bytes[32..])
      Regex::Automata::Wire.write_version(2_u32, bytes[36..])
      bytes[40..].copy_from(payload)
      expect_raises(Regex::Automata::DeserializeError) do
        Regex::Automata::DFA::DFA.from_bytes(bytes)
      end
    end
  end

  it "rejects every truncated prefix and accepts trailing bytes with the correct consumed length" do
    bytes = Regex::Automata::DFA::DFA.new("abc").to_bytes_native_endian[0]
    bytes.size.times do |length|
      expect_raises(Regex::Automata::DeserializeError) do
        Regex::Automata::DFA::DFA.from_bytes(bytes[0, length])
      end
    end
    padded = Bytes.new(bytes.size + 13, 0xA5_u8)
    padded[0, bytes.size].copy_from(bytes)
    Regex::Automata::DFA::DFA.from_bytes(padded)[1].should eq(bytes.size)
  end

  it "accepts initial alignment padding and rejects a misaligned label" do
    bytes = Regex::Automata::DFA::DFA.new("abc").to_bytes_native_endian[0]
    buffer = Bytes.new(bytes.size + 8, 0_u8)
    buffer[4, bytes.size].copy_from(bytes)
    Regex::Automata::DFA::DFA.from_bytes(buffer)[1].should eq(bytes.size + 4)
    buffer.fill(0_u8)
    buffer[1, bytes.size].copy_from(bytes)
    expect_raises(Regex::Automata::DeserializeError, /alignment mismatch/) do
      Regex::Automata::DFA::DFA.from_bytes(buffer)
    end
  end

  it "returns padding separately from length and safely decodes unchecked input" do
    %w(abc).each do |pattern|
      dfa = Regex::Automata::DFA::DFA.new(pattern)
      bytes, padding = dfa.to_bytes_native_endian
      bytes.size.should eq(dfa.write_to_len + padding)
      decoded, consumed = Regex::Automata::DFA::DFA.from_bytes_unchecked(bytes)
      consumed.should eq(bytes.size)
      decoded.try_search_fwd(Regex::Automata::Input.new(pattern)).should eq(Regex::Automata::HalfMatch.must(0, 3))
    end
  end
end

describe "dense native validation regressions" do
  it "ports dense.rs::regression_validation_order with an independently empty match table" do
    dfa = Regex::Automata::DFA::DFA.new("abc")
    bytes = dfa.to_bytes_native_endian[0]
    offset = 312 + dfa.state_len * dfa.stride * 4 + dfa.st.write_to_len
    after_matches = offset + dfa.ms.write_to_len
    malformed = Bytes.new(bytes.size - dfa.ms.write_to_len + 12, 0_u8)
    malformed[0, offset].copy_from(bytes[0, offset])
    Regex::Automata::Wire.write_u32(0_u32, malformed[offset..])
    Regex::Automata::Wire.write_u32(1_u32, malformed[offset + 4..])
    Regex::Automata::Wire.write_u32(0_u32, malformed[offset + 8..])
    malformed[offset + 12..].copy_from(bytes[after_matches..])
    expect_raises(Regex::Automata::DeserializeError, /match state length mismatch/) do
      Regex::Automata::DFA::DFA.from_bytes(malformed)
    end
  end

  it "rejects forged component counts before reserving storage" do
    dfa = Regex::Automata::DFA::DFA.new("abc")
    bytes = dfa.to_bytes_native_endian[0]
    starts_offset = 312 + dfa.state_len * dfa.stride * 4
    matches_offset = starts_offset + dfa.st.write_to_len
    {
      48,                                              # transition state count
      starts_offset + 264,                             # optional pattern count
      matches_offset,                                  # match slices
      matches_offset + 4 + dfa.ms.slices.size * 8 + 4, # pattern-ID count
    }.each do |offset|
      malformed = bytes.dup
      Regex::Automata::Wire.write_u32(0x7FFF_FFFF_u32, malformed[offset..])
      expect_raises(Regex::Automata::DeserializeError) do
        Regex::Automata::DFA::DFA.from_bytes(malformed)
      end
    end
  end
end

describe "dense native ownership and option metadata" do
  it "preserves Rust's Some(0) pattern starts and absent universal starts" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.starts_for_each_pattern(true))
      .build_many([] of String)
    dfa.starts_for_each_pattern?.should be_true
    decoded = Regex::Automata::DFA::DFA.from_bytes(dfa.to_bytes_native_endian[0])[0]
    decoded.starts_for_each_pattern?.should be_true
    decoded.to_owned.starts_for_each_pattern?.should be_true
    decoded.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::Pattern, Regex::Automata::PatternID.new(0))).should eq(Regex::Automata::StateID::ZERO)
    bytes = Regex::Automata::DFA::DFA.new("abc").to_bytes_native_endian[0].dup
    states = IO::ByteFormat::SystemEndian.decode(UInt32, bytes[48, 4]).to_i
    stride2 = IO::ByteFormat::SystemEndian.decode(UInt32, bytes[52, 4]).to_i
    starts_offset = 312 + (states << stride2) * 4
    Regex::Automata::Wire.write_u32(UInt32::MAX, bytes[starts_offset + 268..])
    Regex::Automata::Wire.write_u32(UInt32::MAX, bytes[starts_offset + 272..])
    decoded = Regex::Automata::DFA::DFA.from_bytes(bytes)[0]
    decoded.universal_start_state(Regex::Automata::Anchored::No).should be_nil
    decoded.universal_start_state(Regex::Automata::Anchored::Yes).should be_nil
    decoded.to_owned.universal_start_state(Regex::Automata::Anchored::No).should be_nil
  end

  it "copies owned graphs directly and preserves the pinned decoder's quit-bucket behavior" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.quit('A'.ord.to_u8, true))
      .build("abc")
    owned = dfa.to_owned
    owned.quitset.includes?(0xC1_u8).should be_false
    decoded = Regex::Automata::DFA::DFA.from_bytes(dfa.to_bytes_native_endian[0])[0]
    decoded.start_state(Regex::Automata::StartConfig.new(0xC1_u8)).should be_a(Regex::Automata::QuitStartError)
    start = dfa.start_state(Regex::Automata::StartConfig.new).as(Regex::Automata::StateID)
    dfa.set_transition(start, Regex::Automata::Unit.u8('a'.ord.to_u8), Regex::Automata::StateID::ZERO)
    owned.try_search_fwd(Regex::Automata::Input.new("abc")).should eq(Regex::Automata::HalfMatch.must(0, 3))
    dfa.try_search_fwd(Regex::Automata::Input.new("abc")).should be_nil
  end

  it "validates accelerator padding chunks and retains valid raw accelerator storage" do
    dfa = Regex::Automata::DFA::DFA.new("abc")
    bytes = dfa.to_bytes_native_endian[0]
    special_offset = 312 + dfa.state_len * dfa.stride * 4 + dfa.st.write_to_len + dfa.ms.write_to_len
    accels_offset = special_offset + 32
    count = IO::ByteFormat::SystemEndian.decode(UInt32, bytes[accels_offset, 4]).to_i
    count.should be > 0
    malformed = bytes.dup
    malformed[accels_offset + 8] = 4_u8
    expect_raises(Regex::Automata::DeserializeError, /accelerator bytes/) do
      Regex::Automata::DFA::DFA.from_bytes(malformed)
    end
    # Rust allows an extra accelerator, even if no state indexes it.
    expanded = Bytes.new(bytes.size + 8, 0_u8)
    boundary = accels_offset + 4 + count * 8
    expanded[0, boundary].copy_from(bytes[0, boundary])
    Regex::Automata::Wire.write_u32((count + 1).to_u32, expanded[accels_offset..])
    expanded[boundary..][8, 32].copy_from(bytes[boundary, 32])
    decoded = Regex::Automata::DFA::DFA.from_bytes(expanded)[0]
    decoded.to_owned.to_bytes_native_endian[0].should eq(expanded)
  end
end

describe "dense Rust stride padding" do
  it "retains arbitrary unused u32 padding while validating every logical transition" do
    dfa = Regex::Automata::DFA::DFA.new("abc")
    dfa.alphabet_len.should be < dfa.stride
    bytes = dfa.to_bytes_native_endian[0]
    Regex::Automata::Wire.write_u32(UInt32::MAX, bytes[312 + dfa.alphabet_len * 4..])
    decoded = Regex::Automata::DFA::DFA.from_bytes(bytes)[0]
    decoded.try_search_fwd(Regex::Automata::Input.new("abc")).should eq(Regex::Automata::HalfMatch.must(0, 3))
    decoded.to_owned.to_bytes_native_endian[0].should eq(bytes)
    Regex::Automata::Wire.write_u32(UInt32::MAX, bytes[312..])
    expect_raises(Regex::Automata::DeserializeError, /invalid state ID/) do
      Regex::Automata::DFA::DFA.from_bytes(bytes)
    end
  end
end
