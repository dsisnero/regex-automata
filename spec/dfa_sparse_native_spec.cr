require "./spec_helper"

# Exact assertions from tests/gen/sparse/mod.rs at the pinned upstream commit.
describe "Rust sparse DFA wire compatibility" do
  it "loads the checked-in multi_pattern_v2 forward and reverse DFAs" do
    endian = IO::ByteFormat::SystemEndian == IO::ByteFormat::LittleEndian ? "littleendian" : "bigendian"
    base = File.join(__DIR__, "../vendor/regex/regex-automata/tests/gen/sparse")
    forward_bytes = File.read(File.join(base, "multi_pattern_v2_fwd.#{endian}.dfa")).to_slice
    reverse_bytes = File.read(File.join(base, "multi_pattern_v2_rev.#{endian}.dfa")).to_slice
    forward, forward_read = Regex::Automata::DFA::Sparse::DFA.from_bytes(forward_bytes)
    reverse, reverse_read = Regex::Automata::DFA::Sparse::DFA.from_bytes(reverse_bytes)
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

describe "sparse native wire boundaries" do
  %w(
    deserialize_sparse_crash-a1b839d899ced76d5d7d0f78f9edb7a421505838
    deserialize_sparse_crash-dbb8172d3984e7e7d03f4b5f8bb86ecd1460eff9
    deserialize_sparse_crash-0da59c0434eaf35e5a6b470fa9244bb79c72b000
    deserialize_sparse_crash-61fd8e3003bf9d99f6c1e5a8488727eefd234b98
    deserialize_sparse_crash-c383ae07ec5e191422eadc492117439011816570
    deserialize_sparse_crash-d07703ceb94b10dcd9e4acb809f2051420449e2b
    deserialize_sparse_crash-18cfc246f2ddfc3dfc92b0c7893178c7cf65efa9
  ).each do |name|
    it "ports tests/fuzz/sparse.rs payload #{name}" do
      given = File.read(File.join(__DIR__, "../vendor/regex/regex-automata/tests/fuzz/testdata", name)).to_slice
      haystack_len = given[0].to_i
      payload = given[1 + haystack_len..]
      bytes = Bytes.new(40 + payload.size, 0_u8)
      Regex::Automata::Wire.write_label(Regex::Automata::DFA::Sparse::DFA::LABEL, bytes)
      Regex::Automata::Wire.write_endianness_check(bytes[32..])
      Regex::Automata::Wire.write_version(2_u32, bytes[36..])
      bytes[40..].copy_from(payload)
      expect_raises(Regex::Automata::DeserializeError) do
        Regex::Automata::DFA::Sparse::DFA.from_bytes(bytes)
      end
    end
  end

  it "writes both endiannesses with Rust's fixture decode/re-encode behavior" do
    base = File.join(__DIR__, "../vendor/regex/regex-automata/tests/gen/sparse")
    %w(fwd rev).each do |direction|
      native = Regex::Automata::DFA::DFA.native_wire_endian == :little ? "littleendian" : "bigendian"
      bytes = File.read(File.join(base, "multi_pattern_v2_#{direction}.#{native}.dfa")).to_slice
      dfa, read = Regex::Automata::DFA::Sparse::DFA.from_bytes(bytes)
      read.should eq(bytes.size)
      %w(littleendian bigendian).each do |endian|
        expected = File.read(File.join(base, "multi_pattern_v2_#{direction}.#{endian}.dfa")).to_slice.dup
        expected[-16, 16].copy_from(expected[-32, 16])
        actual = endian == "littleendian" ? dfa.to_bytes_little_endian : dfa.to_bytes_big_endian
        actual.should eq(expected)
      end
      opposite = native == "littleendian" ? dfa.to_bytes_big_endian : dfa.to_bytes_little_endian
      expect_raises(Regex::Automata::DeserializeError, /endianness mismatch/) do
        Regex::Automata::DFA::Sparse::DFA.from_bytes(opposite)
      end
    end
  end

  it "accepts unaligned native bytes and reports consumed length with trailing bytes" do
    bytes = Regex::Automata::DFA::Sparse::DFA.new("abc").to_bytes_native_endian
    buffer = Bytes.new(bytes.size + 7, 0xA5_u8)
    buffer[1, bytes.size].copy_from(bytes)
    decoded, read = Regex::Automata::DFA::Sparse::DFA.from_bytes(buffer[1..])
    read.should eq(bytes.size)
    decoded.try_search_fwd(Regex::Automata::Input.new("abc")).should eq(Regex::Automata::HalfMatch.must(0, 3))
    bytes.size.times do |length|
      expect_raises(Regex::Automata::DeserializeError) do
        Regex::Automata::DFA::Sparse::DFA.from_bytes(bytes[0, length])
      end
    end
  end

  it "ports sparse.rs::regression_start_state_not_match" do
    dfa = Regex::Automata::DFA::Sparse::DFA.new("abc")
    bytes = dfa.to_bytes_native_endian
    packed_len = IO::ByteFormat::SystemEndian.decode(UInt32, bytes[312, 4]).to_i
    starts_offset = 316 + packed_len
    12.times do |index|
      Regex::Automata::Wire.write_state_id(dfa.special.min_match, bytes[starts_offset + 276 + index * 4..])
    end
    expect_raises(Regex::Automata::DeserializeError, /start states cannot be match states/) do
      Regex::Automata::DFA::Sparse::DFA.from_bytes(bytes)
    end
  end
end

describe "packed sparse conversion" do
  it "repairs every byte, EOI, start, match, and accelerator ID over adversarial dense configurations" do
    {true, false}.each do |classes|
      {true, false}.each do |minimize|
        {true, false}.each do |accelerate|
          dense = Regex::Automata::DFA::Builder.new
            .configure(Regex::Automata::DFA::DFA.config.byte_classes(classes).minimize(minimize)
              .accelerate(accelerate).starts_for_each_pattern(true).specialize_start_states(true))
            .build_many(["a[^x]*x", "(?-u:\\b)foo", "bar$"])
          sparse = dense.to_sparse
          bytes = sparse.to_bytes_native_endian
          packed_len = IO::ByteFormat::SystemEndian.decode(UInt32, bytes[312, 4]).to_i
          remap = [] of Regex::Automata::StateID
          offset = 0
          while offset < packed_len
            id = Regex::Automata::StateID.new(offset)
            remap << id
            state = Regex::Automata::DFA::Sparse::State.new(bytes[316, packed_len], id)
            offset += state.write_to_len
          end
          remap.size.should eq(dense.state_len)
          sparse.memory_usage.should eq(packed_len + dense.st.table.size * 4)
          remap.each_with_index do |id, index|
            dense_id = dense.to_state_id(index)
            256.times do |byte|
              sparse.next_state(id, byte.to_u8).should eq(remap[dense.to_index(dense.next_state(dense_id, byte.to_u8))])
            end
            sparse.next_eoi_state(id).should eq(remap[dense.to_index(dense.next_eoi_state(dense_id))])
            sparse.is_match_state?(id).should eq(dense.is_match_state?(dense_id))
            sparse.match_len(id).should eq(dense.match_len(dense_id))
            sparse.accelerator(id).should eq(dense.accelerator(dense_id))
            sparse.match_len(id).times { |pattern| sparse.match_pattern(id, pattern).should eq(dense.match_pattern(dense_id, pattern)) }
          end
          dense.starts.each do |id, anchored, start, pattern|
            byte = case start
                   when Regex::Automata::Start::Text        then nil
                   when Regex::Automata::Start::WordByte    then 'a'.ord.to_u8
                   when Regex::Automata::Start::NonWordByte then ' '.ord.to_u8
                   when Regex::Automata::Start::LineLF      then '\n'.ord.to_u8
                   when Regex::Automata::Start::LineCR      then '\r'.ord.to_u8
                   else                                          nil
                   end
            next if start == Regex::Automata::Start::CustomLineTerminator
            config = Regex::Automata::StartConfig.new(byte, anchored, pattern)
            sparse.start_state(config).should eq(remap[dense.to_index(id)])
          end
          ["aZZx", "foo", "bar", "", "@foo aZZx"].each do |haystack|
            sparse.try_search_fwd(Regex::Automata::Input.new(haystack)).should eq(dense.try_search_fwd(Regex::Automata::Input.new(haystack)))
          end
        end
      end
    end
  end
end

describe "sparse start metadata and ownership" do
  it "preserves Some(0) pattern starts through conversion, native bytes, and owned copies" do
    dense = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.starts_for_each_pattern(true))
      .build_many([] of String)
    sparse = dense.to_sparse
    decoded = Regex::Automata::DFA::Sparse::DFA.from_bytes(sparse.to_bytes_native_endian)[0]
    {sparse, decoded, decoded.to_owned}.each do |dfa|
      dfa.starts_for_each_pattern?.should be_true
      dfa.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::Pattern, Regex::Automata::PatternID::ZERO)).should eq(Regex::Automata::StateID::ZERO)
    end
  end

  it "retains custom line-terminator starts and quit-before-anchor error precedence" do
    dense = Regex::Automata::DFA::Builder.new
      .syntax { |parser| parser.line_terminator('@'.ord.to_u8) }
      .thompson { |compiler| compiler.look_matcher(Regex::Automata::LookMatcher.new('@'.ord.to_u8)) }
      .build("(?m)^abc$")
    sparse = dense.to_sparse
    decoded = Regex::Automata::DFA::Sparse::DFA.from_bytes(sparse.to_bytes_native_endian)[0]
    {sparse, decoded}.each do |dfa|
      dfa.try_search_fwd(Regex::Automata::Input.new("@abc@").range(1...4)).should eq(Regex::Automata::HalfMatch.must(0, 4))
    end
    sparse = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.start_kind(Regex::Automata::StartKind::Anchored).quit('A'.ord.to_u8, true))
      .build("abc").to_sparse
    sparse.start_state(Regex::Automata::StartConfig.new('A'.ord.to_u8, Regex::Automata::Anchored::No)).should be_a(Regex::Automata::QuitStartError)
    sparse.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::No)).should be_a(Regex::Automata::UnsupportedAnchoredStartError)
  end

  it "owns conversion bytes and keeps prefilter attachment independent across views and copies" do
    prefilter = Regex::Automata::Prefilter.new(Regex::Automata::MatchKind::LeftmostFirst, ["abc"]) || raise "expected usable prefilter"
    dense = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.prefilter(prefilter))
      .build("abc")
    sparse = dense.to_sparse
    view = sparse.as_ref
    owned = sparse.to_owned
    sparse.set_prefilter(nil)
    view.get_prefilter.should be(prefilter)
    owned.get_prefilter.should be(prefilter)
    start = dense.start_state(Regex::Automata::StartConfig.new).as(Regex::Automata::StateID)
    dense.set_transition(start, Regex::Automata::Unit.u8('a'.ord.to_u8), Regex::Automata::StateID::ZERO)
    {sparse, view, owned}.each do |dfa|
      dfa.try_search_fwd(Regex::Automata::Input.new("abc")).should eq(Regex::Automata::HalfMatch.must(0, 3))
    end
  end

  it "rejects forged sparse component counts without oversized allocations" do
    bytes = Regex::Automata::DFA::Sparse::DFA.new("abc").to_bytes_native_endian
    packed_len = IO::ByteFormat::SystemEndian.decode(UInt32, bytes[312, 4]).to_i
    {48, 312, 316 + packed_len + 264}.each do |offset|
      malformed = bytes.dup
      Regex::Automata::Wire.write_u32(0x7FFF_FFFF_u32, malformed[offset..])
      expect_raises(Regex::Automata::DeserializeError) do
        Regex::Automata::DFA::Sparse::DFA.from_bytes(malformed)
      end
    end
  end
end
