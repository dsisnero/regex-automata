require "./types"
require "./transition_table"

module Regex::Automata
  # Flattened storage for match state pattern IDs.
  #
  # Rust's dense DFA stores match metadata separately from its transition
  # table. We keep the same flattened representation here. The slice index is
  # keyed by the transition-table state index so searches avoid a hash lookup
  # when resolving a match state.
  class MatchStates
    getter pattern_len : Int32

    @state_to_match_index : Array(Int32?)
    @tt : TransitionTable?
    @slices : Array(Tuple(Int32, Int32))
    @pattern_ids : Array(PatternID)

    def self.empty(pattern_len : Int32 = 0) : MatchStates
      new([] of Int32?, [] of Tuple(Int32, Int32), [] of PatternID, pattern_len, nil)
    end

    def self.from_states(states : Array(Regex::Automata::DFA::State), tt : TransitionTable?, pattern_len : Int32? = nil) : MatchStates
      state_to_match_index = Array(Int32?).new(states.size, nil)
      slices = [] of Tuple(Int32, Int32)
      pattern_ids = [] of PatternID
      max_pattern_id = -1

      states.each_with_index do |state, index|
        state.match.each do |pattern_id|
          max_pattern_id = Math.max(max_pattern_id, pattern_id.to_i)
        end
        next if state.match.empty?

        state_to_match_index[index] = slices.size
        slices << {pattern_ids.size, state.match.size}
        pattern_ids.concat(state.match)
      end

      inferred_pattern_len = max_pattern_id >= 0 ? max_pattern_id + 1 : 0
      new(state_to_match_index, slices, pattern_ids, pattern_len || inferred_pattern_len, tt)
    end

    def initialize(@state_to_match_index : Array(Int32?), @slices : Array(Tuple(Int32, Int32)), @pattern_ids : Array(PatternID), @pattern_len : Int32, @tt : TransitionTable?)
    end

    def match_state?(id : StateID) : Bool
      !match_index(id).nil?
    end

    def match_len(id : StateID) : Int32
      index = match_index(id)
      return 0 unless index

      _, len = @slices[index]
      len
    end

    def match_pattern(id : StateID, index : Int32) : PatternID
      return PatternID.new(0) if @pattern_len == 1

      slice_index = match_index(id)
      raise IndexError.new unless slice_index

      start, len = @slices[slice_index]
      raise IndexError.new unless 0 <= index < len
      @pattern_ids[start + index]
    end

    private def match_index(id : StateID) : Int32?
      state_index = if tt = @tt
                      tt.to_index(id)
                    else
                      id.to_i
                    end
      return nil if state_index < 0 || state_index >= @state_to_match_index.size

      @state_to_match_index[state_index]
    end
  end
end
