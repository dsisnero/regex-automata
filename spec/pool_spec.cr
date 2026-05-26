require "./spec_helper"

describe Regex::Automata::Pool(Array(Char)) do
  it "creates fresh values when the pool is empty and reuses values after put" do
    calls = 0
    pool = Regex::Automata::Pool(Array(Char)).new do
      calls += 1
      ['a']
    end

    first = pool.get
    first.value.should eq(['a'])
    first.value << 'b'
    first.put

    second = pool.get
    second.value.should eq(['a', 'b'])
    second.put

    calls.should eq(1)
  end

  it "supports the upstream-style class put helper" do
    calls = 0
    pool = Regex::Automata::Pool(Int32).new do
      calls += 1
      7
    end

    guard = pool.get
    guard.value.should eq(7)
    Regex::Automata::PoolGuard.put(guard)

    pool.get.value.should eq(7)
    calls.should eq(1)
  end

  it "returns distinct values for simultaneous gets" do
    calls = 0
    pool = Regex::Automata::Pool(Array(Char)).new do
      calls += 1
      ['a']
    end

    g1 = pool.get
    g2 = pool.get

    g1.value << 'b'
    g2.value << 'c'

    g1.value.should eq(['a', 'b'])
    g2.value.should eq(['a', 'c'])

    g1.put
    g2.put

    calls.should eq(2)
  end
end
