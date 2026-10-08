require "./spec_helper"

describe Regex::Automata::SparseSet do
  it "preserves insertion order, idempotence, and fixed capacity" do
    set = Regex::Automata::SparseSet.new(3)
    a = Regex::Automata::StateID.new(0)
    b = Regex::Automata::StateID.new(2)

    set.capacity.should eq(3)
    set.len.should eq(0)
    set.insert(b).should be_true
    set.insert(a).should be_true
    set.insert(b).should be_false
    set.iter.to_a.should eq([b, a])
    set.contains(a).should be_true
    set.contains(Regex::Automata::StateID.new(1)).should be_false
    set.len.should eq(2)
  end

  it "clears automatically when resized" do
    set = Regex::Automata::SparseSet.new(4)
    set.insert(Regex::Automata::StateID.new(1))
    set.resize(8)

    set.capacity.should eq(8)
    set.is_empty.should be_true
    set.iter.to_a.should be_empty
  end

  it "forgets prior sparse indices with a logical clear" do
    set = Regex::Automata::SparseSet.new(4)
    old = Regex::Automata::StateID.new(3)
    fresh = Regex::Automata::StateID.new(1)
    set.insert(old)
    set.clear
    set.insert(fresh).should be_true

    set.contains(old).should be_false
    set.iter.to_a.should eq([fresh])
  end

  it "clears and swaps paired sets" do
    sets = Regex::Automata::SparseSets.new(3)
    sets.set1.insert(Regex::Automata::StateID.new(1))
    sets.set2.insert(Regex::Automata::StateID.new(2))
    sets.swap
    sets.set1.iter.to_a.should eq([Regex::Automata::StateID.new(2)])
    sets.clear
    sets.set1.is_empty.should be_true
    sets.set2.is_empty.should be_true
  end
end
