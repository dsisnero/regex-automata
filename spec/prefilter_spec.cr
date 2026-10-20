require "./spec_helper"

describe Regex::Automata::Prefilter do
  # Rust's Choice::new probes these in order; >64 literals force Teddy to
  # decline and exercise the ByteSet/Aho-Corasick fallback paths.
  it "selects the pinned Rust scalar and fallback strategies" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    one = Regex::Automata::Prefilter.new(kind, ["x"]).not_nil!
    one.strategy_name.should eq("memchr")
    one.memory_usage.should eq(0)
    one.is_fast.should be_true

    two = Regex::Automata::Prefilter.new(kind, ["x", "y"]).not_nil!
    two.strategy_name.should eq("memchr2")
    two.memory_usage.should eq(0)
    three = Regex::Automata::Prefilter.new(kind, ["x", "y", "z"]).not_nil!
    three.strategy_name.should eq("memchr3")
    three.memory_usage.should eq(0)

    substring = Regex::Automata::Prefilter.new(kind, ["needle"]).not_nil!
    substring.strategy_name.should eq("memmem")
    substring.memory_usage.should eq(6)
    substring.is_fast.should be_true

    bytes = (0..64).map { |n| Bytes[128_u8 + n.to_u8] }
    byte_set = Regex::Automata::Prefilter.new(kind, bytes).not_nil!
    byte_set.strategy_name.should eq("byteset")
    byte_set.memory_usage.should eq(0)
    byte_set.is_fast.should be_false

    many = (0..64).map { |n| "prefix-#{n}" }
    aho = Regex::Automata::Prefilter.new(kind, many).not_nil!
    aho.strategy_name.should eq("aho-corasick")
    aho.is_fast.should be_false
    aho.memory_usage.should be > 0
  end

  it "keeps byte-set and Aho candidates inside spans with leftmost priority" do
    kind = Regex::Automata::MatchKind::All
    byte_set = Regex::Automata::Prefilter.new(
      kind, (0..64).map { |n| Bytes[128_u8 + n.to_u8] }
    ).not_nil!
    hay = Bytes[0_u8, 129_u8, 130_u8, 0_u8]
    byte_set.find(hay, Regex::Automata::Span.new(2, 4)).should eq(
      Regex::Automata::Span.new(2, 3)
    )
    byte_set.prefix(hay, Regex::Automata::Span.new(0, 4)).should be_nil
    byte_set.prefix(hay, Regex::Automata::Span.new(1, 2)).should eq(
      Regex::Automata::Span.new(1, 2)
    )

    needles = (0..62).map { |n| "unused-#{n}" } + ["abc", "b"]
    aho = Regex::Automata::Prefilter.new(kind, needles).not_nil!
    aho.find("abc".to_slice, Regex::Automata::Span.new(0, 3)).should eq(
      Regex::Automata::Span.new(0, 3)
    )
    aho.find("abc".to_slice, Regex::Automata::Span.new(1, 3)).should eq(
      Regex::Automata::Span.new(1, 2)
    )
  end

  it "finds the earliest candidate and preserves leftmost-first tie order" do
    haystack = "Hello samwise".to_slice
    span = Regex::Automata::Span.new(0, haystack.size)

    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["samwise", "sam"]
    ).not_nil!
    pre.find(haystack, span).should eq(Regex::Automata::Span.new(6, 13))

    reversed = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["sam", "samwise"]
    ).not_nil!
    reversed.find(haystack, span).should eq(Regex::Automata::Span.new(6, 9))
  end

  it "matches prefixes anchored at the start of the search span" do
    haystack = "Hello Bruce Springsteen!".to_slice
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["Bruce ", "Patti "]
    ).not_nil!

    pre.prefix(haystack, Regex::Automata::Span.new(0, haystack.size)).should be_nil
    pre.prefix(haystack, Regex::Automata::Span.new(6, haystack.size)).should eq(
      Regex::Automata::Span.new(6, 12)
    )
  end

  it "never returns a candidate outside the supplied search span" do
    haystack = "needle...needle".to_slice
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["needle"]
    ).not_nil!

    pre.find(haystack, Regex::Automata::Span.new(1, 9)).should be_nil
    pre.find(haystack, Regex::Automata::Span.new(1, haystack.size)).should eq(
      Regex::Automata::Span.new(9, 15)
    )
    pre.prefix(haystack, Regex::Automata::Span.new(1, haystack.size)).should be_nil

    byte = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["."]
    ).not_nil!
    byte.find(haystack, Regex::Automata::Span.new(0, 6)).should be_nil
    byte.find(haystack, Regex::Automata::Span.new(0, 10)).should eq(
      Regex::Automata::Span.new(6, 7)
    )
  end

  it "extracts prefix literals from HIRs" do
    hir = Regex::Syntax.parse("(Bruce|Patti) \\w+")
    pre = Regex::Automata::Prefilter.from_hir_prefix(
      Regex::Automata::MatchKind::LeftmostFirst,
      hir
    ).not_nil!

    haystack = "Hello Patti Scialfa!".to_slice
    pre.find(haystack, Regex::Automata::Span.new(0, haystack.size)).should eq(
      Regex::Automata::Span.new(6, 12)
    )
    pre.max_needle_len.should eq(6)
    pre.memory_usage.should be > 0
  end

  it "extracts and optimizes prefixes across multiple HIRs" do
    hirs = [
      Regex::Syntax.parse("(Bruce|Patti) \\w+"),
      Regex::Syntax.parse("Mrs?\\. Doubtfire"),
    ]

    pre = Regex::Automata::Prefilter.from_hirs_prefix(
      Regex::Automata::MatchKind::LeftmostFirst,
      hirs
    ).not_nil!

    haystack = "Hello Mrs. Doubtfire".to_slice
    pre.find(haystack, Regex::Automata::Span.new(0, haystack.size)).should eq(
      Regex::Automata::Span.new(6, 20)
    )
  end

  it "rejects empty needle sets and empty-prefix literal extractions" do
    Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      [] of String
    ).should be_nil

    Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      [""]
    ).should be_nil

    empty_hir = Regex::Syntax.parse("a*")
    Regex::Automata::Prefilter.from_hir_prefix(
      Regex::Automata::MatchKind::LeftmostFirst,
      empty_hir
    ).should be_nil
  end

  it "marks tiny single-byte and short multi-substring sets as fast" do
    fast = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["a", "b", "c"]
    ).not_nil!
    fast.is_fast.should be_true
    fast.find("zzcbax".to_slice, Regex::Automata::Span.new(0, 6)).should eq(
      Regex::Automata::Span.new(2, 3)
    )

    multi = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["alpha", "beta"]
    ).not_nil!
    # Rust can select packed Teddy here. The Crystal Aho fallback is visible
    # until phase 2b ports the packed matcher and its fast-path admission.
    multi.strategy_name.should eq("aho-corasick")
    multi.is_fast.should be_true
  end

  it "keeps leftmost start and pattern priority through failure-link overlaps" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["samwise", "sam", "wise"]
    ).not_nil!
    haystack = "xxsamwise".to_slice
    span = Regex::Automata::Span.new(0, haystack.size)
    pre.find_with_index(haystack, span).should eq({0, Regex::Automata::Span.new(2, 9)})
    pre.prefix_with_index(haystack, span).should be_nil
    pre.prefix_with_index(haystack, Regex::Automata::Span.new(2, 9)).should eq(
      {0, Regex::Automata::Span.new(2, 9)}
    )

    overlapping = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["aab", "ab"]
    ).not_nil!
    overlapping.find("aab".to_slice, Regex::Automata::Span.new(0, 3)).should eq(
      Regex::Automata::Span.new(0, 3)
    )
  end

  it "treats a single substring needle as fast" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["ing"]
    ).not_nil!

    pre.is_fast.should be_true

    # The first `a` is only a candidate; the search must continue to the
    # later complete literal without scanning every non-candidate offset.
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["aba"]
    ).not_nil!
    pre.find("a---aba".to_slice, Regex::Automata::Span.new(0, 7)).should eq(
      Regex::Automata::Span.new(4, 7)
    )
  end
end
