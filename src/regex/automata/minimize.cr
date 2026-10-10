module Regex::Automata::DFA
  # A dense-DFA minimizer that merges equivalent states while preserving the
  # current port's observable state metadata.
  class Minimizer
    def initialize(@dfa : DFA)
    end

    def run : DFA
      return @dfa if @dfa.states.size <= 2

      partitions = initial_partitions
      part_of = partition_map(partitions)
      waiting = partitions.map(&.dup)
      incoming = incoming_transitions

      until waiting.empty?
        splitter = waiting.pop
        break unless splitter

        incoming.first.size.times do |unit|
          sources = incoming_sources(incoming, splitter, unit)
          next if sources.empty?

          partition_count = partitions.size
          partition_count.times do |partition_id|
            group = partitions[partition_id]
            inside, outside = split(group, sources)
            next if inside.empty? || outside.empty?

            partitions[partition_id] = inside
            new_partition_id = partitions.size
            partitions << outside
            outside.each { |state| part_of[state] = new_partition_id }

            if waiting_index = waiting.index(group)
              waiting[waiting_index] = inside
              waiting << outside
            elsif inside.size <= outside.size
              waiting << inside
            else
              waiting << outside
            end
          end
        end
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

    private def partition_map(partitions : Array(Array(Int32))) : Array(Int32)
      part_of = Array.new(@dfa.states.size, 0)
      partitions.each_with_index do |group, partition_id|
        group.each do |state_index|
          part_of[state_index] = partition_id
        end
      end
      part_of
    end

    # Reverse transition index, with the final slot representing EOI. This is
    # the same input relation used by Rust's Hopcroft worklist.
    private def incoming_transitions : Array(Array(Array(Int32)))
      alphabet_len = @dfa.states.first.next.size + 1
      incoming = Array.new(@dfa.states.size) { Array.new(alphabet_len) { [] of Int32 } }
      @dfa.states.each_with_index do |state, source|
        state.next.each_with_index do |target, unit|
          incoming[logical_state_index(target)][unit] << source
        end
        incoming[logical_state_index(state.eoi_next)][alphabet_len - 1] << source
      end
      incoming
    end

    private def incoming_sources(incoming : Array(Array(Array(Int32))), splitter : Array(Int32), unit : Int32) : Array(Bool)
      sources = Array.new(@dfa.states.size, false)
      splitter.each do |target|
        incoming[target][unit].each { |source| sources[source] = true }
      end
      sources
    end

    private def split(group : Array(Int32), sources : Array(Bool)) : Tuple(Array(Int32), Array(Int32))
      inside = [] of Int32
      outside = [] of Int32
      group.each { |state| sources[state] ? inside << state : outside << state }
      {inside, outside}
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
        state.next = representative.next.map { |id| StateID.new(old_to_new[logical_state_index(id)]) }
        state.eoi_next = StateID.new(old_to_new[logical_state_index(representative.eoi_next)])
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
