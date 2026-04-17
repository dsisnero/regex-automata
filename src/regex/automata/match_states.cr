require "./types"
require "./transition_table"

module Regex::Automata
  # Flattened storage for match state pattern IDs.
  #
  # Rust's dense DFA stores match metadata separately from its transition
  # table. We keep the same flattened representation here, but use an explicit
  # state->slice index because this port does not yet reorder match states into
  # one contiguous region.
  class MatchStates
    getter pattern_len : Int32

    @state_to_match_index : Hash(Int32, Int32)
    @slices : Array(Tuple(Int32, Int32))
    @pattern_ids : Array(PatternID)

    def self.empty(pattern_len : Int32 = 0) : MatchStates
      new({} of Int32 => Int32, [] of Tuple(Int32, Int32), [] of PatternID, pattern_len)
    end

    def self.from_states(states : Array(Regex::Automata::DFA::State), tt : TransitionTable?, pattern_len : Int32? = nil) : MatchStates
      state_to_match_index = {} of Int32 => Int32
      slices = [] of Tuple(Int32, Int32)
      pattern_ids = [] of PatternID
      max_pattern_id = -1

      states.each_with_index do |state, index|
        state.match.each do |pattern_id|
          max_pattern_id = Math.max(max_pattern_id, pattern_id.to_i)
        end
        next if state.match.empty?

        public_state_id = tt ? tt.not_nil!.to_state_id(index) : state.id
        state_to_match_index[public_state_id.to_i] = slices.size
        slices << {pattern_ids.size, state.match.size}
        pattern_ids.concat(state.match)
      end

      inferred_pattern_len = max_pattern_id >= 0 ? max_pattern_id + 1 : 0
      new(state_to_match_index, slices, pattern_ids, pattern_len || inferred_pattern_len)
    end

    def initialize(@state_to_match_index : Hash(Int32, Int32), @slices : Array(Tuple(Int32, Int32)), @pattern_ids : Array(PatternID), @pattern_len : Int32)
    end

    def match_state?(id : StateID) : Bool
      @state_to_match_index.has_key?(id.to_i)
    end

    def match_len(id : StateID) : Int32
      index = @state_to_match_index[id.to_i]?
      return 0 unless index

      _, len = @slices[index]
      len
    end

    def match_pattern(id : StateID, index : Int32) : PatternID
      return PatternID.new(0) if @pattern_len == 1

      slice_index = @state_to_match_index[id.to_i]?
      raise IndexError.new unless slice_index

      start, len = @slices[slice_index]
      raise IndexError.new unless 0 <= index < len
      @pattern_ids[start + index]
    end
  end
end
