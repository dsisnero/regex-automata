require "./spec_helper"

describe Regex::Automata::Lazy(Int32) do
  it "initializes once and returns the cached value" do
    calls = 0
    lazy = Regex::Automata::Lazy(Int32).new do
      calls += 1
      42
    end

    lazy.get.should eq(42)
    lazy.get.should eq(42)
    calls.should eq(1)
  end

  it "supports the upstream-style class getter" do
    calls = 0
    lazy = Regex::Automata::Lazy(String).new do
      calls += 1
      "value"
    end

    Regex::Automata::Lazy.get(lazy).should eq("value")
    Regex::Automata::Lazy.get(lazy).should eq("value")
    calls.should eq(1)
  end
end
