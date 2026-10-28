require "./spec_helper"

# Pinned oracle: nfa/thompson/nfa.rs DenseTransitions and the Dense arms in
# nfa/thompson/{pikevm,backtrack}.rs. The compiler's conversion is disabled.
describe "Thompson dense-state representation" do
  it "follows only nonzero byte targets and never follows EOI" do
    targets = Array(Regex::Automata::StateID).new(256, Regex::Automata::StateID::ZERO)
    targets['a'.ord] = Regex::Automata::StateID.new(2)
    dense = Regex::Automata::NFA::Dense.new(targets)

    dense.matches_byte('a'.ord.to_u8).should eq(Regex::Automata::StateID.new(2))
    dense.matches_byte('b'.ord.to_u8).should be_nil
    dense.matches_unit(Regex::Automata::Unit.u8('a'.ord.to_u8)).should eq(Regex::Automata::StateID.new(2))
    dense.matches_unit(Regex::Automata::Unit.eoi(256)).should be_nil
    dense.matches("a".to_slice, 0).should eq(Regex::Automata::StateID.new(2))
    dense.matches("a".to_slice, 1).should be_nil
    dense.iter.to_a.should eq([
      Regex::Automata::NFA::Transition.new('a'.ord.to_u8, 'a'.ord.to_u8, Regex::Automata::StateID.new(2)),
    ])
  end

  it "lets PikeVM and bounded backtracker consume an explicit Dense state" do
    sid = Regex::Automata::StateID.new(1)
    targets = Array(Regex::Automata::StateID).new(256, Regex::Automata::StateID::ZERO)
    targets['a'.ord] = Regex::Automata::StateID.new(2)
    states = [
      Regex::Automata::NFA::Fail.new,
      Regex::Automata::NFA::Dense.new(targets),
      Regex::Automata::NFA::Match.new(Regex::Automata::PatternID.new(0)),
    ] of Regex::Automata::NFA::State
    nfa = Regex::Automata::NFA::NFA.new(
      states, sid, sid, [sid], true, false,
      Regex::Automata::GroupInfo.new([[nil] of String?])
    )

    pike = Regex::Automata::NFA::PikeVM.builder.build_from_nfa(nfa)
    backtrack = Regex::Automata::NFA::Backtrack::BoundedBacktracker.builder.build_from_nfa(nfa)
    pike.is_match(pike.create_cache, "a").should be_true
    pike.is_match(pike.create_cache, "b").should be_false
    pike.search_slots(pike.create_cache, Regex::Automata::Input.new("a"), [] of Int32?).should eq(Regex::Automata::PatternID.new(0))
    matched = Regex::Automata::PatternSet.new(1)
    pike.which_overlapping_matches(pike.create_cache, Regex::Automata::Input.new("a"), matched)
    matched.contains(Regex::Automata::PatternID.new(0)).should be_true
    backtrack.try_is_match(backtrack.create_cache, "a").should be_true
    backtrack.try_is_match(backtrack.create_cache, "b").should be_false
    nfa.transitions(sid, 'a'.ord.to_u8).should eq(Set{Regex::Automata::StateID.new(2)})
    nfa.transitions(sid, 'b'.ord.to_u8).should be_empty
    nfa.epsilon_closure(Set{sid}).should eq(Set{sid})
    nfa.has_empty.should be_false
    sparse_states = [
      Regex::Automata::NFA::Fail.new,
      Regex::Automata::NFA::Sparse.new([
        Regex::Automata::NFA::Transition.new('a'.ord.to_u8, 'a'.ord.to_u8, Regex::Automata::StateID.new(2)),
      ]),
      Regex::Automata::NFA::Match.new(Regex::Automata::PatternID.new(0)),
    ] of Regex::Automata::NFA::State
    sparse = Regex::Automata::NFA::NFA.new(
      sparse_states, sid, sid, [sid], true, false,
      Regex::Automata::GroupInfo.new([[nil] of String?])
    )
    (nfa.memory_usage - sparse.memory_usage).should eq(
      256 * sizeof(Regex::Automata::StateID) - sizeof(Regex::Automata::NFA::Transition)
    )
    nfa.byte_classes.get('a'.ord.to_u8).should_not eq(nfa.byte_classes.get('b'.ord.to_u8))
  end

  it "keeps compiler-generated sparse states sparse at the pinned Rust revision" do
    nfa = Regex::Automata::NFA::NFA.new("[a-zA-Z0-9]")
    nfa.states.any?(&.is_a?(Regex::Automata::NFA::Dense)).should be_false
  end
end
