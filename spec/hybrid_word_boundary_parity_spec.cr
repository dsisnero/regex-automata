require "./spec_helper"

# These expected low-level half matches come from the pinned Rust hybrid DFA.
# A global NFA look set must not turn a word assertion in one branch into a
# requirement for an empty match supplied by a different branch.
describe "vendor hybrid mixed word-assertion parity" do
  it "searches a non-matching unanchored span once, as Rust's forward loop does" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.prefilter(nil))
      .build("(?-u:\\b)ZQZQ")
    cache = dfa.create_cache
    haystack = "a" * 256

    dfa.try_search_fwd(cache, Regex::Automata::Input.new(haystack)).should be_nil
    cache.bytes_searched.should eq(haystack.bytesize)
  end

  it "does not rescan the suffix after each false-positive prefilter candidate" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["a"]
    ).not_nil!
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.prefilter(prefilter).specialize_start_states(true))
      .build("ab")
    cache = dfa.create_cache
    haystack = "aX" * 128

    dfa.try_search_fwd(cache, Regex::Automata::Input.new(haystack)).should be_nil
    cache.bytes_searched.should eq(haystack.bytesize)
  end

  it "distinguishes word and non-word byte classes for a bare boundary" do
    dfa = Regex::Automata::Hybrid::Builder.new.build("(?-u:\\b)")
    dfa.try_search_fwd(dfa.create_cache, Regex::Automata::Input.new(" a")).should eq(
      Regex::Automata::HalfMatch.must(0, 1)
    )
  end

  [
    {"a*|(?-u:\\b)", "  "},
    {"(?-u:\\b)|a*", "  "},
    {"a*|(?-u:\\b)", " abc"},
    {"(?-u:\\b)|a*", " abc"},
    {"(?:(?-u:\\b)foo)?", "  "},
    {"(?-u:\\b)|(?:)", "  "},
  ].each do |pattern, haystack|
    it "does not invent or suppress an empty match for #{pattern.inspect} on #{haystack.inspect}" do
      dfa = Regex::Automata::Hybrid::Builder.new.build(pattern)
      dfa.try_search_fwd(dfa.create_cache, Regex::Automata::Input.new(haystack)).should eq(
        Regex::Automata::HalfMatch.must(0, 0)
      )
    end
  end

  it "keeps multi-pattern match priority independent of another pattern's word look" do
    dfa = Regex::Automata::Hybrid::Builder.new.build_many(["a*", "(?-u:\\b)"])
    dfa.try_search_fwd(dfa.create_cache, Regex::Automata::Input.new("  ")).should eq(
      Regex::Automata::HalfMatch.must(0, 0)
    )
  end
end
