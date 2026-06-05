require "./spec_helper"

describe "quit-after-match regressions" do
  it "returns the recorded match instead of a later quit error for input searches" do
    automaton : Regex::Automata::Automaton = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::Config.new.quit('z'.ord.to_u8, true))
      .build("abc")

    automaton
      .try_search_fwd(Regex::Automata::Input.new("abcyz").span(0...4))
      .should eq(Regex::Automata::HalfMatch.must(0, 3))
  end

  it "returns an earlier match instead of a later quit error in slice searches" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::Config.new.quit('z'.ord.to_u8, true))
      .build("abc")

    dfa.try_search_fwd("abcyz".to_slice).should eq(
      {3, [Regex::Automata::PatternID.new(0)]}
    )
  end
end
