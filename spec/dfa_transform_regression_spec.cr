require "./spec_helper"

describe "DFA graph transformations" do
  it "preserves EOI and byte transitions when reducing classes repeatedly" do
    ["a", "ab", "a|b", "[a-z]", "a*", "a?", "a$"].each do |pattern|
      original = Regex::Automata::DFA::Builder.new.build(pattern)
      reduced = original.reduce_byte_classes
      ["", "a", "ab", "b", "z", "aa", "!", "a!"].each do |input|
        reduced.find_longest_match(input).should eq(original.find_longest_match(input))
        reduced.reduce_byte_classes.find_longest_match(input).should eq(original.find_longest_match(input))
      end
    end
  end

  it "preserves delayed matches and reserved states when removing unreachable states" do
    original = Regex::Automata::DFA::Builder.new.build("ab")
    table = original.tt.as(Regex::Automata::DFA::TransitionTable)
    states = original.states.dup
    states << Regex::Automata::DFA::State.new(Regex::Automata::StateID.new(states.size), original.byte_classes)
    extended = Regex::Automata::DFA::DFA.new(states, nil,
      Regex::Automata::StateID.new(table.to_index(original.start)), original.byte_classifier,
      Regex::Automata::StateID.new(table.to_index(original.start_anchored)))
    optimized = extended.remove_dead_states
    optimized.size.should be < extended.size
    ["", "ab", "ab!", "a", "!"].each do |input|
      optimized.find_longest_match(input).should eq(extended.find_longest_match(input))
    end
    optimized.is_dead_state?(Regex::Automata::StateID.new(0)).should be_true
  end
end
