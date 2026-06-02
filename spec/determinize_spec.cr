require "./spec_helper"

describe Regex::Automata::Determinize do
  it "sets vendored look-behind assertions for a text start" do
    nfa = Regex::Automata::HirCompiler.new.build("(?m)\\A\\b^a")
    builder = Regex::Automata::Determinize::StateBuilderEmpty.new.into_matches

    Regex::Automata::Determinize.set_lookbehind_from_start(
      nfa,
      Regex::Automata::Start::Text,
      builder
    )
    state = builder.into_nfa.to_state

    state.look_have.should eq(
      Regex::Automata::LookSet.empty
        .insert(Regex::Automata::Look::Start)
        .insert(Regex::Automata::Look::StartLF)
        .insert(Regex::Automata::Look::StartCRLF)
        .insert(Regex::Automata::Look::WordStartHalfAscii)
        .insert(Regex::Automata::Look::WordStartHalfUnicode)
    )
  end

  it "computes epsilon closure through satisfied conditional look states only" do
    builder = Regex::Automata::NFA::Builder.new
    match_id = builder.add_state(Regex::Automata::NFA::Match.new(Regex::Automata::PatternID::ZERO))
    look_id = builder.add_state(
      Regex::Automata::NFA::Look.new(
        Regex::Automata::NFA::Look::Kind::StartText,
        match_id
      )
    )
    builder.set_start_anchored(look_id)
    builder.set_start_unanchored(look_id)
    builder.add_pattern_start(look_id)
    nfa = builder.build

    stack = [] of Regex::Automata::StateID
    set = Regex::Automata::SparseSet.new(nfa.states.size.to_i32)
    Regex::Automata::Determinize.epsilon_closure(
      nfa,
      look_id,
      Regex::Automata::LookSet.singleton(Regex::Automata::Look::Start),
      stack,
      set
    )

    got = [] of Regex::Automata::StateID
    set.each { |sid| got << sid }
    got.should eq([look_id, match_id])

    set.clear
    Regex::Automata::Determinize.epsilon_closure(
      nfa,
      look_id,
      Regex::Automata::LookSet.empty,
      stack,
      set
    )
    got = [] of Regex::Automata::StateID
    set.each { |sid| got << sid }
    got.should eq([look_id])
  end
end
