module Regex::Automata::DFA
  # A dense-DFA minimizer that merges equivalent states while preserving the
  # current port's observable state metadata.
  class Minimizer
    def initialize(@dfa : DFA)
    end

    def run : DFA
      return @dfa if @dfa.states.size <= 2

      partitions = initial_partitions
      loop do
        part_of = partition_map(partitions)
        refined = refine_partitions(part_of)
        break if refined == partitions
        partitions = refined
      end

      rebuild(partitions)
    end

    private def initial_partitions : Array(Array(Int32))
      grouped = {} of Tuple(Symbol, Array(PatternID), LookSet, LookSet, Bool, Bool) => Array(Int32)

      @dfa.states.each_with_index do |state, index|
        kind = case index
               when DEAD_STATE_ID.to_i
                 :dead
               when QUIT_STATE_ID.to_i
                 :quit
               else
                 :normal
               end
        key = {kind, state.match, state.look_need, state.look_have, state.is_from_word?, state.is_half_crlf?}
        (grouped[key] ||= [] of Int32) << index
      end

      grouped.values.sort_by(&.first)
    end

    private def refine_partitions(part_of : Array(Int32)) : Array(Array(Int32))
      grouped = {} of Tuple(Symbol, Array(PatternID), LookSet, LookSet, Bool, Bool, Array(Int32), Int32) => Array(Int32)

      @dfa.states.each_with_index do |state, index|
        kind = case index
               when DEAD_STATE_ID.to_i
                 :dead
               when QUIT_STATE_ID.to_i
                 :quit
               else
                 :normal
               end
        transitions = state.next.map { |id| part_of[id.to_i] }
        key = {
          kind,
          state.match,
          state.look_need,
          state.look_have,
          state.is_from_word?,
          state.is_half_crlf?,
          transitions,
          part_of[state.eoi_next.to_i],
        }
        (grouped[key] ||= [] of Int32) << index
      end

      grouped.values.sort_by(&.first)
    end

    private def partition_map(partitions : Array(Array(Int32))) : Array(Int32)
      part_of = Array.new(@dfa.states.size, 0)
      partitions.each_with_index do |group, partition_id|
        group.each do |state_index|
          part_of[state_index] = partition_id
        end
      end
      part_of
    end

    private def rebuild(partitions : Array(Array(Int32))) : DFA
      ordered = partitions.sort_by(&.first)
      old_to_new = Array.new(@dfa.states.size, 0)
      ordered.each_with_index do |group, new_index|
        group.each do |old_index|
          old_to_new[old_index] = new_index
        end
      end

      new_states = [] of State
      new_accelerators = Array.new(ordered.size) { Bytes.empty }
      ordered.each_with_index do |group, new_index|
        old_index = group.first
        representative = @dfa.states[old_index]
        state = representative.dup(StateID.new(new_index))
        state.next = representative.next.map { |id| StateID.new(old_to_new[id.to_i]) }
        state.eoi_next = StateID.new(old_to_new[representative.eoi_next.to_i])
        new_states << state
        new_accelerators[new_index] = @dfa.accelerators[old_index]
      end

      remap_id = ->(id : StateID) do
        old_index = logical_state_index(id)
        StateID.new(old_to_new[old_index])
      end

      start_table = @dfa.st.remap { |id| remap_id.call(id) }
      minimized = DFA.new(
        new_states,
        nil,
        remap_id.call(@dfa.st.unanchored),
        @dfa.byte_classifier,
        remap_id.call(@dfa.st.anchored),
        new_accelerators,
        @dfa.get_prefilter,
        @dfa.quitset,
        @dfa.flags,
        start_table
      )

      minimized.special.set_no_special_start_states if @dfa.special.no_start_states?
      minimized
    end

    private def logical_state_index(id : StateID) : Int32
      if tt = @dfa.tt
        tt.to_index(id)
      else
        id.to_i
      end
    end
  end
end
