require "./spec_helper"

describe Regex::Automata do
  it "can be required" do
    # Just test that the module exists
    Regex::Automata.should_not be_nil
  end

  it "has version constant" do
    Regex::Automata::VERSION.should be_a(String)
  end

  it "defines PatternID struct" do
    pid = Regex::Automata::PatternID.new(1)
    pid.to_i.should eq(1)
  end

  it "defines StateID struct" do
    sid = Regex::Automata::StateID.new(2)
    sid.to_i.should eq(2)
  end

  it "exposes the primary engine namespaces and the DFA dead-state sentinel" do
    Regex::Automata::DFA::DFA.name.should eq("Regex::Automata::DFA::DFA")
    Regex::Automata::Hybrid::DFA.name.should eq("Regex::Automata::Hybrid::DFA")
    Regex::Automata::Meta::Regex.name.should eq("Regex::Automata::Meta::Regex")
    Regex::Automata::NFA::NFA.name.should eq("Regex::Automata::NFA::NFA")

    Regex::Automata::DFA::DEAD_STATE_ID.should eq(Regex::Automata::StateID::ZERO)
    Regex::Automata::DFA.dead_state?(Regex::Automata::DFA::DEAD_STATE_ID).should be_true
  end
end
