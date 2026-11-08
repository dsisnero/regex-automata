require "./spec_helper"

describe "pinned memchr combined and reverse byte searches" do
  it "rejects invalid packed-pair offsets before entering native code" do
    Regex::Automata::ByteSearch.pair(Bytes[1_u8, 2_u8], -1, 1, Bytes[1_u8, 2_u8], false).should be_nil
    Regex::Automata::ByteSearch.pair(Bytes.empty, 0, 1, Bytes.empty, false).should be_nil
    Regex::Automata::ByteSearch.pair(Bytes[1_u8, 2_u8], 0, 2, Bytes[1_u8, 2_u8], false).should be_nil
  end

  it "preserves bounded first/last candidates across vector sizes and alignments" do
    {% if flag?(:byte_search_scalar) %}
      Regex::Automata::ByteSearch::VECTOR_WIDTH.should eq(0)
    {% elsif flag?(:byte_search_sse2) && flag?(:x86_64) %}
      Regex::Automata::ByteSearch::VECTOR_WIDTH.should eq(16)
    {% elsif flag?(:aarch64) %}
      Regex::Automata::ByteSearch::VECTOR_WIDTH.should eq(16)
    {% end %}
    [0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127].each do |len|
      5.times do |alignment|
        bytes = Bytes.new(len + alignment) { |i| ((i * 73 + 17) % 256).to_u8 }
        window = bytes[alignment, len]
        [Bytes[17_u8], Bytes[17_u8, 255_u8], Bytes[0_u8, 127_u8, 255_u8], Bytes[17_u8, 17_u8, 17_u8]].each do |needles|
          (0..len).each do |at|
            expected = (at...len).find { |i| needles.includes?(window[i]) }
            Regex::Automata::ByteSearch.find(needles, window[at, len - at]).should eq(expected.try { |i| i - at })
            expected_rev = (0...at).to_a.reverse.find { |i| needles.includes?(window[i]) }
            Regex::Automata::ByteSearch.find(needles, window[0, at], reverse: true).should eq(expected_rev)
            Regex::Automata.find_fwd(needles, window, at).should eq(expected)
            Regex::Automata.find_rev(needles, window, at).should eq(expected_rev)
          end
        end
      end
    end
  end
end
