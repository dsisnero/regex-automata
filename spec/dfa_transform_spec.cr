require "./spec_helper"

describe "pinned dense DFA transforms" do
  # Rust src/dfa/minimize.rs::initial_partitions puts every non-match,
  # non-quit state in one initial partition. Look metadata belongs to
  # determinization, not the observable DFA state equivalence relation.
  it "merges equivalent nonmatching rows despite construction look metadata" do
    dead = Regex::Automata::DFA::State.new(Regex::Automata::StateID.new(0), 256)
    quit = Regex::Automata::DFA::State.new(Regex::Automata::StateID.new(1), 256)
    start_a = Regex::Automata::DFA::State.new(
      Regex::Automata::StateID.new(2), 256,
      Regex::Automata::LookSet.new,
      Regex::Automata::LookSet.from_look(Regex::Automata::Look::StartLF)
    )
    start_b = Regex::Automata::DFA::State.new(
      Regex::Automata::StateID.new(3), 256,
      Regex::Automata::LookSet.new,
      Regex::Automata::LookSet.from_look(Regex::Automata::Look::StartCRLF)
    )
    dfa = Regex::Automata::DFA::DFA.new(
      [dead, quit, start_a, start_b], nil,
      Regex::Automata::StateID.new(2), Regex::Automata::ByteClasses.identity,
      Regex::Automata::StateID.new(3)
    )

    minimized = Regex::Automata::DFA::Minimizer.new(dfa).run
    minimized.state_len.should eq(2)
    minimized.try_search_fwd(Regex::Automata::Input.new("anything")).should be_nil
  end

  # Rust dense.rs::Builder::build_from_nfa applies shuffle, minimize, then
  # accelerate. These assertions cover the state-ID repair performed by
  # remapper.rs and the contiguous special ranges after each transform.
  it "preserves starts, matches, transitions and accelerators across transform combinations" do
    patterns = ["(?:ab|ac|ad)*x", "foo$", "bar"]
    baseline = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.accelerate(false))
      .build_many(patterns)
    haystacks = ["", "x", "abacx", "foo", "fooz", "bar", "zzabacxzz", "abacfoo"]

    {false, true}.each do |minimize|
      {false, true}.each do |accelerate|
        {false, true}.each do |specialize|
          dfa = Regex::Automata::DFA::Builder.new
            .configure(Regex::Automata::DFA::DFA.config
              .minimize(minimize)
              .accelerate(accelerate)
              .specialize_start_states(specialize))
            .build_many(patterns)
          table = dfa.tt.not_nil!
          dfa.states.each_index do |index|
            id = table.to_state_id(index)
            table.is_valid(dfa.next_eoi_state(id)).should be_true
            256.times do |byte|
              target = dfa.next_state(id, byte.to_u8)
              table.is_valid(target).should be_true
              if dfa.is_accel_state?(id) && !dfa.accelerator(id).includes?(byte.to_u8)
                target.should eq(id)
              end
            end
          end
          dfa.starts.each do |id, _, _, _|
            table.is_valid(id).should be_true
            dfa.is_match_state?(id).should be_false unless id == Regex::Automata::DFA::DEAD_STATE_ID
          end
          haystacks.each do |haystack|
            dfa.try_search_fwd(Regex::Automata::Input.new(haystack)).should eq(
              baseline.try_search_fwd(Regex::Automata::Input.new(haystack))
            )
          end
        end
      end
    end
  end
end
