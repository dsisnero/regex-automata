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

  it "lets concurrent initializers race and publishes only one result" do
    release = Atomic(Bool).new(false)
    calls = Atomic(Int32).new(0)
    lazy = Regex::Automata::Lazy(Int32).new do
      value = calls.add(1) + 1
      until release.get
        Thread.yield
      end
      value
    end
    results = Channel(Int32).new(2)
    threads = [] of Thread
    2.times do
      threads << Thread.new do
        results.send(lazy.get)
      end
    end

    until calls.get == 2
      Thread.yield
    end
    release.set(true)
    threads.each(&.join)
    first = results.receive
    results.receive.should eq(first)
    calls.get.should eq(2)
    lazy.get.should eq(first)
  end

  it "retries initialization after the creating thread raises" do
    calls = 0
    lazy = Regex::Automata::Lazy(Int32).new do
      calls += 1
      raise "first initialization failed" if calls == 1
      42
    end

    expect_raises(Exception, "first initialization failed") { lazy.get }
    lazy.get.should eq(42)
    calls.should eq(2)
  end

  it "can cache a nil result" do
    calls = 0
    lazy = Regex::Automata::Lazy(Int32?).new do
      calls += 1
      nil
    end

    lazy.get.should be_nil
    lazy.get.should be_nil
    calls.should eq(1)
  end
end
