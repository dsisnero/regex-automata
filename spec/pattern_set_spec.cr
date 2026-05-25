require "./spec_helper"

describe "pattern set" do
  it "tracks inserted pattern ids in ascending order" do
    set = Regex::Automata::PatternSet.new(4)

    set.capacity.should eq(4)
    set.len.should eq(0)
    set.is_empty.should be_true
    set.is_full.should be_false

    set.insert(Regex::Automata::PatternID.new(3)).should be_true
    set.insert(Regex::Automata::PatternID.new(1)).should be_true
    set.insert(Regex::Automata::PatternID.new(1)).should be_false
    set.insert(Regex::Automata::PatternID.new(0)).should be_true

    set.contains(Regex::Automata::PatternID.new(0)).should be_true
    set.contains(Regex::Automata::PatternID.new(2)).should be_false
    set.len.should eq(3)
    set.iter.to_a.should eq([
      Regex::Automata::PatternID.new(0),
      Regex::Automata::PatternID.new(1),
      Regex::Automata::PatternID.new(3),
    ])
  end

  it "supports reverse iteration and clearing" do
    set = Regex::Automata::PatternSet.new(3)
    set.insert(Regex::Automata::PatternID.new(0))
    set.insert(Regex::Automata::PatternID.new(2))

    iter = set.iter
    iter.next_back.should eq(Regex::Automata::PatternID.new(2))
    iter.next.should eq(Regex::Automata::PatternID.new(0))
    iter.next.should be_nil

    set.clear
    set.is_empty.should be_true
    set.iter.to_a.should eq([] of Regex::Automata::PatternID)
  end

  it "removes pattern ids and tracks fullness" do
    set = Regex::Automata::PatternSet.new(2)
    set.insert(Regex::Automata::PatternID.new(0))
    set.insert(Regex::Automata::PatternID.new(1))

    set.is_full.should be_true
    set.remove(Regex::Automata::PatternID.new(1)).should be_true
    set.is_full.should be_false
    set.len.should eq(1)
    set.remove(Regex::Automata::PatternID.new(1)).should be_false
  end

  it "reports insufficient capacity on insert" do
    set = Regex::Automata::PatternSet.new(1)

    result = set.try_insert(Regex::Automata::PatternID.new(2))
    result.should be_a(Regex::Automata::PatternSetInsertError)
    error = result.as(Regex::Automata::PatternSetInsertError)
    error.attempted.should eq(Regex::Automata::PatternID.new(2))
    error.capacity.should eq(1)
    error.message.should eq("failed to insert pattern ID 2 into pattern set with insufficient capacity of 1")

    raised = expect_raises(Regex::Automata::PatternSetInsertError) do
      set.insert(Regex::Automata::PatternID.new(2))
    end
    raised.capacity.should eq(1)
  end
end
