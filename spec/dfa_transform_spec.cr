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

module Regex::Automata
  describe DFA::DFA do
    it "removes unreachable states without losing delayed matches" do
      original = DFA::Builder.new.build("ab")
      # The constructor takes row indices. Materialized states expose
      # premultiplied IDs in v0.2.0.
      states = original.states.map_with_index do |state, index|
        copy = state.dup(StateID.new(index))
        copy.next.map! { |id| StateID.new(original.to_index(id)) }
        copy.eoi_next = StateID.new(original.to_index(copy.eoi_next))
        copy
      end
      states << DFA::State.new(StateID.new(states.size), original.byte_classes)
      extended = DFA::DFA.new(states, nil, StateID.new(original.to_index(original.start)),
        original.byte_classifier, StateID.new(original.to_index(original.start_anchored)))
      optimized = extended.remove_dead_states
      optimized.size.should be < extended.size
      state = optimized.next_state(optimized.start, 'a'.ord.to_u8)
      state = optimized.next_state(state, 'b'.ord.to_u8)
      optimized.is_match_state?(state).should be_false
      optimized.is_match_state?(optimized.next_eoi_state(state)).should be_true
      optimized.find_longest_match("ab").should eq({2, [PatternID.new(0)]})
      optimized.find_longest_match("ab!").should eq({2, [PatternID.new(0)]})
      optimized.find_longest_match("!").should be_nil
      optimized.is_dead_state?(DFA::DEAD_STATE_ID).should be_true
    end

    it "keeps contextual and per-pattern starts and reports quit after pruning" do
      config = DFA::Config.new.starts_for_each_pattern(true).quit('!'.ord.to_u8, true)
      original = DFA::Builder.new.configure(config).build_many(["(?m:^ab)", "cd"])
      original.add_empty_state
      pruned = original.remove_dead_states
      pruned.size.should be < original.size

      line_start = Input.new("\nab").span(1...3).anchored(Anchored::Yes)
      mid_line = Input.new("xab").span(1...3).anchored(Anchored::Yes)
      pattern_start = Input.new("cd").anchored_pattern(PatternID.new(1))
      pruned.try_search_fwd(line_start).should eq(HalfMatch.must(0, 3))
      pruned.try_search_fwd(mid_line).should be_nil
      pruned.try_search_fwd(pattern_start).should eq(HalfMatch.must(1, 2))
      pruned.try_search_fwd(Input.new("xx!ab")).should eq(MatchError.quit('!'.ord.to_u8, 2))
    end
  end
end
