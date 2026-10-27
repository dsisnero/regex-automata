require "./spec_helper"

describe "scalar prefilter consumers" do
  # Source-characterization for pinned util/prefilter/memchr.rs::Memchr3:
  # three one-byte needles choose one bounded candidate before each engine
  # resumes its own search. No direct Rust unit test exists for this module.
  it "uses bounded memchr3 candidates across dense, hybrid, NFA, and Meta" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      [Bytes[97_u8], Bytes[98_u8], Bytes[99_u8]]
    ).not_nil!
    pre.strategy_name.should eq("memchr3")
    pattern = "(?:a|b|c)z"
    input = Regex::Automata::Input.new(Bytes[0_u8, 97_u8, 122_u8, 0_u8]).span(1...3)
    expected = Regex::Automata::Match.must(0, 1...3)
    half = Regex::Automata::HalfMatch.must(0, 3)

    dense = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.prefilter(pre))
      .build(pattern)
    dense.try_search_fwd(input).should eq(half)

    hybrid = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.prefilter(pre))
      .build(pattern)
    hybrid.try_search_fwd(hybrid.create_cache, input).should eq(half)

    pike = Regex::Automata::NFA::PikeVM.builder
      .configure(Regex::Automata::NFA::PikeVM.config.prefilter(pre))
      .build(pattern)
    pike.find(pike.create_cache, input).should eq(expected)

    backtrack = Regex::Automata::NFA::Backtrack::BoundedBacktracker.builder
      .configure(Regex::Automata::NFA::Backtrack::BoundedBacktracker.config.prefilter(pre))
      .build(pattern)
    backtrack.try_find(backtrack.create_cache, input).should eq(expected)

    meta = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.auto_prefilter(false).prefilter(pre))
      .build(pattern)
    meta.find(input).should eq(expected)
  end
end
