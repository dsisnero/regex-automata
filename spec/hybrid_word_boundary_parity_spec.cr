require "./spec_helper"

# These expected low-level half matches come from the pinned Rust hybrid DFA.
# A global NFA look set must not turn a word assertion in one branch into a
# requirement for an empty match supplied by a different branch.
describe "vendor hybrid mixed word-assertion parity" do
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
