require "./spec_helper"

describe Regex::Automata::DFA::Builder do
  it "builds an anchored UTF-8 DFA for a Unicode word repetition" do
    config = Regex::Automata::DFA::Config.new
      .start_kind(Regex::Automata::DFA::StartKind::Anchored)
      .accelerate(false)
      .prefilter(nil)

    dfa = Regex::Automata::DFA::Builder.new(config).build("\\w+")

    dfa.is_utf8?.should be_true
    dfa.states.size.should be > 2
    dfa.find_longest_match("é".to_slice).should eq({2, [Regex::Automata::PatternID.new(0)]})
  end
end
