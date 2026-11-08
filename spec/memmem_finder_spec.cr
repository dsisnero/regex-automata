require "./spec_helper"

class Regex::Automata::MemmemFinder
  def suffix_for_spec(needle : Bytes, minimal : Bool)
    suffix(needle, minimal)
  end
end

describe "pinned memchr 2.8.1 substring finder" do
  it "ports both forward suffix factorizations and periods" do
    finder = Regex::Automata::MemmemFinder.new(Bytes.empty)
    # arch/all/twoway.rs::tests::suffix_forward, in source order.
    {"a", "ab", "ba", "abc", "acb", "cba", "abcabc",
     "abcabcabc", "abczz", "zzabc", "aaa", "foobar"}.zip(
      [{"a", 1, "a", 1}, {"ab", 2, "b", 1}, {"a", 1, "ba", 2},
       {"abc", 3, "c", 1}, {"acb", 3, "cb", 2}, {"a", 1, "cba", 3},
       {"abcabc", 3, "cabc", 3}, {"abcabcabc", 3, "cabcabc", 3},
       {"abczz", 5, "zz", 1}, {"abc", 3, "zzabc", 5},
       {"aaa", 1, "aaa", 1}, {"ar", 2, "r", 1}]
    ) do |needle, expected|
      min_pos, min_period = finder.suffix_for_spec(needle.to_slice, true)
      max_pos, max_period = finder.suffix_for_spec(needle.to_slice, false)
      {needle.byte_slice(min_pos), min_period, needle.byte_slice(max_pos), max_period}.should eq(expected)
    end
  end

  it "agrees with exhaustive binary matching including empty and overlapping inputs" do
    words = (0..8).flat_map do |len|
      Array.new(1 << len) { |bits| Bytes.new(len) { |i| bits.bit(i) == 0 ? 0_u8 : 255_u8 } }
    end
    words.select { |word| word.size <= 6 }.each do |needle|
      finder = Regex::Automata::MemmemFinder.new(needle)
      words.each do |haystack|
        expected = (0..(haystack.size - needle.size)).find { |at| haystack[at, needle.size] == needle }
        finder.find(haystack).should eq(expected)
        padded = Bytes.new(16, 127_u8) + haystack
        padded_expected = needle.empty? ? 0 : expected.try { |at| at + 16 }
        finder.find(padded).should eq(padded_expected)
      end
    end
  end

  it "handles long periodic, near-periodic, binary and last-position candidates" do
    ["a" * 127 + "b", "ab" * 64, "a" * 64 + "b" + "a" * 63,
     "\x00\xff" * 64].each do |needle|
      haystack = "a" * 8192 + needle
      finder = Regex::Automata::MemmemFinder.new(needle.to_slice)
      finder.find(haystack.to_slice).should eq(haystack.byte_index(needle))
      finder.find(("a" * 8192).to_slice).should eq(("a" * 8192).byte_index(needle))
    end
  end

  it "checks long fallback factorizations against a bytewise oracle" do
    rng = Random.new(0x8a17_u64)
    256.times do |case_id|
      period = Bytes.new(rng.rand(1..24)) { rng.rand(4).to_u8 }
      needle = Bytes.new(rng.rand(33..260)) { |i| period[i % period.size] }
      needle[rng.rand(needle.size)] = 255_u8 if case_id.odd?
      prefix = Bytes.new(rng.rand(0..700)) { |i| case_id % 3 == 0 ? period[i % period.size] : rng.rand(4).to_u8 }
      haystack = case_id % 2 == 0 ? prefix + needle : prefix
      expected = (0..(haystack.size - needle.size)).find { |at| haystack[at, needle.size] == needle }
      Regex::Automata::MemmemFinder.new(needle).find(haystack).should eq(expected)
    end
  end

  {% if flag?(:substring_diagnostics) %}
    it "bounds search comparisons linearly on repeated candidate families" do
      [4096, 8192, 16384].each do |len|
        finder = Regex::Automata::MemmemFinder.new(("a" * 127 + "b" + "a" * 128).to_slice)
        finder.find(("a" * len).to_slice).should be_nil
        finder.comparisons.should be <= (4 * len).to_u64
        misleading = Regex::Automata::MemmemFinder.new(("ab" * 63 + "ba" + "ab" * 64).to_slice)
        misleading.find(("ab" * len).to_slice).should be_nil
        misleading.comparisons.should be <= (8 * len).to_u64
        misleading.prefilter_calls.should be <= 50
      end
    end
  {% end %}
end

describe "scalar prefilter storage" do
  it "embeds one-byte needles and lets Meta use the compiled scalar matcher" do
    [["a"], ["a", "b"], ["a", "b", "c"]].each do |needles|
      pre = Regex::Automata::Prefilter.new(Regex::Automata::MatchKind::LeftmostFirst, needles).not_nil!
      pre.retained_needle_bytes.should eq(0)
      pre.memory_usage.should eq(0)
      pre.find("zzcba", Regex::Automata::Span.new(0, 5)).should eq(Regex::Automata::Span.new(needles.size == 1 ? 4 : needles.size == 2 ? 3 : 2, needles.size == 1 ? 5 : needles.size == 2 ? 4 : 3))
      Regex::Automata::Meta::Regex.new(needles.join('|')).find("zzcba").try(&.start).should eq(needles.size == 1 ? 4 : needles.size == 2 ? 3 : 2)
    end
  end
end
