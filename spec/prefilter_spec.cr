require "./spec_helper"

describe Regex::Automata::Prefilter do
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

  it "marks tiny single-byte sets as fast" do
    fast = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["a", "b", "c"]
    ).not_nil!
    fast.is_fast.should be_true

    slow = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["alpha", "beta"]
    ).not_nil!
    slow.is_fast.should be_false
  end

  it "treats a single substring needle as fast" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["ing"]
    ).not_nil!

    pre.is_fast.should be_true
  end
end
