require "./spec_helper"

describe Regex::Automata::Automaton do
  it "supports searching through the abstract automaton API" do
    automaton : Regex::Automata::Automaton = Regex::Automata::DFA::Builder.new.build("abc")

    automaton
      .try_search_fwd(Regex::Automata::Input.new("xyzabcxyz"))
      .should eq(Regex::Automata::HalfMatch.must(0, 6))
  end
end
