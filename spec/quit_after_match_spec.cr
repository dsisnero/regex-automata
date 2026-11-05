require "./spec_helper"

describe "quit-after-match regressions" do
  it "returns Rust's later quit error for bounded input searches" do
    automaton : Regex::Automata::Automaton = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::Config.new.quit('z'.ord.to_u8, true))
      .build("abc")

    automaton
      .try_search_fwd(Regex::Automata::Input.new("abcyz").span(0...4))
      .should eq(Regex::Automata::MatchError.quit('z'.ord.to_u8, 4))
  end

  it "returns Rust's later quit error for slice searches" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::Config.new.quit('z'.ord.to_u8, true))
      .build("abc")

    dfa.try_search_fwd("abcyz".to_slice)
      .should eq(Regex::Automata::MatchError.quit('z'.ord.to_u8, 4))
  end
end
