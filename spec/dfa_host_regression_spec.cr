require "./spec_helper"

describe "DFA host regressions" do
  it "stores materialized transitions in public DFA state-id space" do
    nfa_builder = Regex::Automata::NFA::Builder.new
    ref = nfa_builder.build_literal("a".to_slice)
    nfa_builder.set_start_unanchored(ref.start)
    dfa = Regex::Automata::DFA::Builder.from_nfa(nfa_builder.build).build

    start_state = dfa[dfa.start]
    next_state_id = start_state.next['a'.ord]

    next_state_id.should_not eq(Regex::Automata::DFA::DEAD_STATE_ID)
    dfa[next_state_id].accepting?.should be_true
  end

  it "keeps empty-match acceptance on repetition start states" do
    dfa = Regex::Automata::DFA::Builder.new.build("a*")

    dfa[dfa.start].accepting?.should be_true
    dfa.find_longest_match("aaa").should eq({3, [Regex::Automata::PatternID.new(0)]})
  end

  it "reports consumed end offsets for literal matches" do
    dfa = Regex::Automata::DFA::Builder.new.build("hello")

    dfa.find_longest_match("hello").should eq({5, [Regex::Automata::PatternID.new(0)]})
  end

  it "keeps delayed empty matches from drifting to the end of the haystack" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure { |config| config.accelerate(false).minimize(false) }
      .build("a|")

    dfa.try_search_fwd("bba".to_slice).should eq({0, [Regex::Automata::PatternID.new(0)]})
    dfa.try_search_fwd(Regex::Automata::Input.new("abba").span(1...4)).should eq(
      Regex::Automata::HalfMatch.must(0, 1)
    )
  end

  it "keeps the unanchored prefix when building regex DFAs from multiple patterns" do
    re = Regex::Automata::DFA::Regex.builder.build_many([
      "(?-u:\\b)[a-zA-Z]+(?-u:\\b)",
      "(?m)^\\S+$",
      "(?Rm)^\\S+$",
    ])

    re.find("@ abcd @").should eq(Regex::Automata::Match.must(0, 2...6))
  end

  it "does not treat arbitrary state index 1 as a synthetic quit state" do
    state0 = Regex::Automata::DFA::State.new(Regex::Automata::StateID.new(0), 256)
    state1 = Regex::Automata::DFA::State.new(Regex::Automata::StateID.new(1), 256)
    state2 = Regex::Automata::DFA::State.new(Regex::Automata::StateID.new(2), 256)

    state0.set_transition('a'.ord, Regex::Automata::StateID.new(1))
    (0...256).each do |byte|
      next if byte == 'a'.ord
      state0.set_transition(byte, Regex::Automata::StateID.new(2))
    end
    state1.add_match(Regex::Automata::PatternID.new(0))

    dfa = Regex::Automata::DFA::DFA.new(
      [state0, state1, state2],
      nil,
      Regex::Automata::StateID.new(0),
      256
    )
    optimized = dfa.remove_dead_states

    optimized.size.should eq(2)
    optimized[optimized.start].next['a'.ord].should_not eq(Regex::Automata::DFA::DEAD_STATE_ID)
  end
end
