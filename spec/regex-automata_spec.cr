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
end
