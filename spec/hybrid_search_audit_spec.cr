require "./spec_helper"

module Regex::Automata::Hybrid
  class SearchTrackingCache < Cache
    getter updates = 0

    def search_update(at : Int32) : Nil
      @updates += 1
      super
    end

    def reset_updates : Nil
      @updates = 0
    end
  end
end

describe "hybrid search hot paths" do
  it "uses cached untagged transitions during a reverse scan" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .thompson(Regex::Automata::NFA::NFA.config.reverse(true))
      .build("a{50}b")
    cache = Regex::Automata::Hybrid::SearchTrackingCache.new(dfa)
    input = Regex::Automata::Input.new("a" * 50 + "b")

    dfa.try_search_rev(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 0))
    cache.reset_updates
    dfa.try_search_rev(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 0))
    cache.updates.should be < 10
  end

  it "keeps Rust's overlapping search progress when a prefilter exhausts candidates" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["zzz"]
    ).not_nil!
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.prefilter(prefilter))
      .build("zzz")
    cache = dfa.create_cache
    state = Regex::Automata::Hybrid::OverlappingState.start

    dfa.try_search_overlapping_fwd(cache, Regex::Automata::Input.new("abc"), state).should be_nil
    state.get_match.should be_nil
    cache.progress.should_not be_nil
  end

  it "resolves leftmost priority through the reverse DFA after a forward end match" do
    re = Regex::Automata::Hybrid::Regex.new("abc|a")
    cache = re.create_cache
    re.find(cache, "abc").should eq(Regex::Automata::Match.must(0, 0...3))

    re = Regex::Automata::Hybrid::Regex.new_many(["a", "ab"])
    cache = re.create_cache
    re.try_search(cache, Regex::Automata::Input.new("zab")).should eq(
      Regex::Automata::Match.must(0, 1...2)
    )
    re.try_search(cache, Regex::Automata::Input.new("zab").span(1...3)
      .anchored(Regex::Automata::Anchored::Yes)).should eq(
      Regex::Automata::Match.must(0, 1...2)
    )
  end

  it "handles empty matches and bounded context in the two-DFA wrapper" do
    re = Regex::Automata::Hybrid::Regex.new("a*")
    cache = re.create_cache
    re.try_search(cache, Regex::Automata::Input.new("baa")).should eq(
      Regex::Automata::Match.must(0, 0...0)
    )
    re.try_search(cache, Regex::Automata::Input.new("baa").span(1...3)).should eq(
      Regex::Automata::Match.must(0, 1...3)
    )
  end
end
