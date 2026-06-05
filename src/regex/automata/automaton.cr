require "./search"
require "./types"
require "./errors"

module Regex::Automata
  # A trait describing the interface of a deterministic finite automaton (DFA).
  #
  # The primary purpose of this trait is to provide a way of abstracting over
  # different types of DFAs. In this crate, that means dense DFAs and sparse DFAs.
  # (Dense DFAs are fast but memory hungry, whereas sparse DFAs are slower but
  # come with a smaller memory footprint. But they otherwise provide exactly
  # equivalent expressive power.)
  #
  # Normally, a DFA's execution model is very simple. You might have a single
  # start state, zero or more final or "match" states and a function that
  # transitions from one state to the next given the next byte of input.
  # Unfortunately, the interface described by this trait is significantly
  # more complicated than this. The complexity has a number of different
  # reasons, mostly motivated by performance, functionality or space savings.
  # Base class for DFA implementations
  abstract class Automaton
    # Transitions from the current state to the next state, given the next
    # byte of input.
    #
    # Implementations must guarantee that the returned ID is always a valid
    # ID when `current` refers to a valid ID. Moreover, the transition
    # function must be defined for all possible values of `input`.
    abstract def next_state(current : StateID, input : UInt8) : StateID

    # Transitions from the current state to the next state for the special
    # EOI symbol.
    #
    # This routine must be called at the end of every search in a correct
    # implementation of search. Namely, DFAs in this crate delay matches
    # by one byte in order to support look-around operators. Thus, after
    # reaching the end of a haystack, a search implementation must follow one
    # last EOI transition.
    abstract def next_eoi_state(current : StateID) : StateID

    # Returns the start state for the given configuration.
    #
    # This is the base method for computing start states. Implementations
    # should return either a valid state ID or a StartError.
    #
    # # Errors
    #
    # This may return a StartError if the search needs to give up when
    # determining the start state (for example, if it sees a "quit" byte).
    # This can also return an error if the given configuration contains an
    # unsupported Anchored configuration.
    abstract def start_state(config : StartConfig) : StateID | StartError

    # Returns the start state for a forward search.
    #
    # This is a convenience method that converts the given Input to a
    # StartConfig and calls start_state. If an error occurs, it is converted
    # from a StartError to a MatchError.
    #
    # # Errors
    #
    # This may return a MatchError if the search needs to give up when
    # determining the start state (for example, if it sees a "quit" byte).
    # This can also return an error if the given Input contains an
    # unsupported Anchored configuration.
    def start_state_forward(input : Input) : StateID | MatchError
      config = StartConfig.from_input_forward(input)
      result = start_state(config)
      return result if result.is_a?(StateID)

      case result
      when QuitStartError
        # For forward search, the quit byte is at position start-1
        offset = input.start > 0 ? input.start - 1 : 0
        MatchError.quit(result.byte, offset)
      when UnsupportedAnchoredStartError
        MatchError.unsupported_anchored(result.mode, result.pattern)
      else
        MatchError.unsupported_anchored(input.anchored, input.pattern)
      end
    end

    # Returns the start state for a reverse search.
    #
    # This is a convenience method that converts the given Input to a
    # StartConfig and calls start_state. If an error occurs, it is converted
    # from a StartError to a MatchError.
    #
    # # Errors
    #
    # This may return a MatchError if the search needs to give up when
    # determining the start state (for example, if it sees a "quit" byte).
    # This can also return an error if the given Input contains an
    # unsupported Anchored configuration.
    def start_state_reverse(input : Input) : StateID | MatchError
      config = StartConfig.from_input_reverse(input)
      result = start_state(config)
      return result if result.is_a?(StateID)

      case result
      when QuitStartError
        # For reverse search, the quit byte is at position end
        offset = input.end
        MatchError.quit(result.byte, offset)
      when UnsupportedAnchoredStartError
        MatchError.unsupported_anchored(result.mode, result.pattern)
      else
        MatchError.unsupported_anchored(input.anchored, input.pattern)
      end
    end

    # Returns true if and only if the given state ID corresponds to a "special"
    # state. Special states are states that have some kind of significance,
    # like dead states, quit states, match states, start states or accelerated
    # states.
    abstract def is_special_state?(id : StateID) : Bool

    # Returns true if and only if the given state ID corresponds to a dead
    # state. A dead state is a state that can never lead to a match. Once
    # a DFA enters a dead state, it will never leave it.
    abstract def is_dead_state?(id : StateID) : Bool

    # Returns true if and only if the given state ID corresponds to a quit
    # state. A quit state is a state that is entered whenever the DFA stops
    # a search prematurely (for example, when it sees a "quit" byte).
    abstract def is_quit_state?(id : StateID) : Bool

    # Returns true if and only if the given state ID corresponds to a match
    # state. A match state indicates that a match has been found.
    abstract def is_match_state?(id : StateID) : Bool

    # Returns true if and only if the given state ID corresponds to a start
    # state. A start state is where a search begins.
    abstract def is_start_state?(id : StateID) : Bool

    # Returns true if and only if the given state ID corresponds to an
    # accelerated state. An accelerated state is a state where most of its
    # transitions loop back to itself and only a small number of transitions
    # lead to other states.
    abstract def is_accel_state?(id : StateID) : Bool

    # Returns the number of patterns in this automaton.
    abstract def pattern_len : Int32

    # Returns the number of matches in the given state.
    #
    # If the given state is not a match state, then this returns 0.
    abstract def match_len(id : StateID) : Int32

    # Returns the pattern ID for the match at the given index in the given
    # state.
    #
    # If the given state is not a match state or if the index is out of
    # bounds, then this raises an error.
    abstract def match_pattern(id : StateID, index : Int32) : PatternID

    # Returns true if and only if this automaton can match the empty string.
    abstract def has_empty? : Bool

    # Returns true if and only if this automaton is guaranteed to be valid
    # for UTF-8 input.
    abstract def is_utf8? : Bool

    # Returns true if and only if this automaton is always anchored at the
    # start of a search.
    abstract def is_always_start_anchored? : Bool

    # Returns the accelerator bytes for the given state.
    #
    # If the given state is not an accelerated state, then this returns an
    # empty slice.
    abstract def accelerator(id : StateID) : Bytes

    # Executes a forward search and returns a match if one is found.
    #
    # This is the core search routine for forward searches.
    # Returns either a Tuple(match_position, pattern_ids) or nil if no match,
    # or a MatchError if an error occurred.
    abstract def try_search_fwd(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError

    # Executes a forward search using the full input configuration.
    #
    # This honors the search span within the context of the complete haystack,
    # which matters for look-around at the boundaries of the span.
    def try_search_fwd(input : Input) : HalfMatch? | MatchError
      return nil if input.is_done

      start_state = start_state_forward(input)
      return start_state if start_state.is_a?(MatchError)

      current_state = start_state.as(StateID)
      last_match : HalfMatch? = nil
      at = input.start

      while at < input.end
        next_state = next_state(current_state, input.haystack[at])
        return last_match || MatchError.quit(input.haystack[at], at) if is_quit_state?(next_state)
        break if is_dead_state?(next_state)

        current_state = next_state
        if is_match_state?(current_state)
          last_match = HalfMatch.new(match_pattern(current_state, 0), at)
          return last_match if input.get_earliest
        end
        at += 1
      end

      if at == input.end
        current_state = if trailing = input.haystack[input.end]?
                          next_state(current_state, trailing)
                        else
                          next_eoi_state(current_state)
                        end
        if input.end < input.haystack.size && is_quit_state?(current_state)
          return last_match || MatchError.quit(input.haystack[input.end], input.end)
        end
        if is_match_state?(current_state)
          offset = input.end < input.haystack.size ? input.end : input.haystack.size
          last_match = HalfMatch.new(match_pattern(current_state, 0), offset)
        end
      end

      last_match
    end

    # Executes a reverse search and returns a match if one is found.
    #
    # This is the core search routine for reverse searches.
    # Returns either a Tuple(match_position, pattern_ids) or nil if no match,
    # or a MatchError if an error occurred.
    abstract def try_search_rev(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError

    # Executes a reverse search using the full input configuration.
    #
    # This honors the search span within the context of the complete haystack,
    # which matters for look-around at the boundaries of the span.
    def try_search_rev(input : Input) : HalfMatch? | MatchError
      return nil if input.is_done

      start_state = start_state_reverse(input)
      return start_state if start_state.is_a?(MatchError)

      current_state = start_state.as(StateID)
      last_match : HalfMatch? = nil

      if input.start == input.end
        current_state = if input.start > 0
                          next_state(current_state, input.haystack[input.start - 1])
                        else
                          next_eoi_state(current_state)
                        end
        return MatchError.quit(input.haystack[input.start - 1], input.start - 1) if input.start > 0 && is_quit_state?(current_state)
        return HalfMatch.new(match_pattern(current_state, 0), input.start) if is_match_state?(current_state)
        return nil
      end

      at = input.end - 1
      loop do
        next_state = next_state(current_state, input.haystack[at])
        return MatchError.quit(input.haystack[at], at) if is_quit_state?(next_state)
        break if is_dead_state?(next_state)

        current_state = next_state
        if is_match_state?(current_state)
          last_match = HalfMatch.new(match_pattern(current_state, 0), at + 1)
          return last_match if input.get_earliest
        end

        break if at == input.start
        at -= 1
      end

      if at == input.start
        current_state = if input.start > 0
                          next_state(current_state, input.haystack[input.start - 1])
                        else
                          next_eoi_state(current_state)
                        end
        return MatchError.quit(input.haystack[input.start - 1], input.start - 1) if input.start > 0 && is_quit_state?(current_state)
        last_match = HalfMatch.new(match_pattern(current_state, 0), input.start) if is_match_state?(current_state)
      end

      last_match
    end

    # Executes a forward overlapping search.
    #
    # This is used when searching for overlapping matches.
    abstract def try_search_overlapping_fwd(slice : Bytes) : Array(Tuple(Int32, Array(PatternID))) | MatchError

    # Executes an overlapping forward search using explicit search state.
    #
    # On success, the given state is updated. Callers should inspect
    # `state.get_match` to retrieve the most recent match, if any.
    def try_search_overlapping_fwd(input : Input, state : OverlappingState) : Nil | MatchError
      state.mat = nil
      return nil if input.is_done

      pre = input.get_anchored == Anchored::No ? get_prefilter : nil
      universal_start = !universal_start_state(Anchored::No).nil?

      current_state = if sid = state.id
                        if next_match_index = state.next_match_index
                          if next_match_index < match_len(sid)
                            state.next_match_index = next_match_index + 1
                            state.mat = HalfMatch.new(match_pattern(sid, next_match_index), state.at)
                            return skip_empty_utf8_splits_overlapping_fwd(input, state)
                          end
                        end
                        state.at += 1
                        return nil if state.at > input.end
                        sid
                      else
                        state.at = input.start
                        sid = start_state_forward(input)
                        return sid if sid.is_a?(MatchError)
                        sid.as(StateID)
                      end

      while state.at < input.end
        current_state = next_state(current_state, input.haystack[state.at])
        state.id = current_state
        if is_special_state?(current_state)
          if is_start_state?(current_state)
            if pre
              # Prefilters are not implemented yet in this port.
            elsif is_accel_state?(current_state)
              needles = accelerator(current_state)
              state.at = Regex::Automata.find_fwd(needles, input.haystack, state.at + 1) || input.end
              next
            end
          elsif is_match_state?(current_state)
            state.next_match_index = 1
            state.mat = HalfMatch.new(match_pattern(current_state, 0), state.at)
            return skip_empty_utf8_splits_overlapping_fwd(input, state)
          elsif is_accel_state?(current_state)
            needles = accelerator(current_state)
            state.at = Regex::Automata.find_fwd(needles, input.haystack, state.at + 1) || input.end
            next
          elsif is_dead_state?(current_state)
            return nil
          else
            return MatchError.quit(input.haystack[state.at], state.at)
          end
        end
        state.at += 1
      end

      overlap_eoi_fwd(input, state, current_state)
    end

    # Executes an overlapping reverse search using explicit search state.
    #
    # On success, the given state is updated. Callers should inspect
    # `state.get_match` to retrieve the most recent match, if any.
    def try_search_overlapping_rev(input : Input, state : OverlappingState) : Nil | MatchError
      state.mat = nil
      return nil if input.is_done

      current_state = if sid = state.id
                        if next_match_index = state.next_match_index
                          if next_match_index < match_len(sid)
                            state.next_match_index = next_match_index + 1
                            state.mat = HalfMatch.new(match_pattern(sid, next_match_index), state.at)
                            return skip_empty_utf8_splits_overlapping_rev(input, state)
                          end
                        end

                        if state.rev_eoi
                          return nil
                        elsif state.at == input.start
                          state.rev_eoi = true
                        else
                          state.at -= 1
                        end
                        sid
                      else
                        sid = start_state_reverse(input)
                        return sid if sid.is_a?(MatchError)

                        state.id = sid.as(StateID)
                        if input.start == input.end
                          state.rev_eoi = true
                        else
                          state.at = input.end - 1
                        end
                        sid.as(StateID)
                      end

      until state.rev_eoi
        current_state = next_state(current_state, input.haystack[state.at])
        state.id = current_state
        if is_special_state?(current_state)
          if is_start_state?(current_state)
            if is_accel_state?(current_state)
              needles = accelerator(current_state)
              state.at = Regex::Automata.find_rev(needles, input.haystack, state.at).try(&.+(1)) || input.start
            end
          elsif is_match_state?(current_state)
            state.next_match_index = 1
            state.mat = HalfMatch.new(match_pattern(current_state, 0), state.at + 1)
            return skip_empty_utf8_splits_overlapping_rev(input, state)
          elsif is_accel_state?(current_state)
            needles = accelerator(current_state)
            state.at = Regex::Automata.find_rev(needles, input.haystack, state.at).try(&.+(1)) || input.start
          elsif is_dead_state?(current_state)
            return nil
          else
            return MatchError.quit(input.haystack[state.at], state.at)
          end
        end

        break if state.at == input.start
        state.at -= 1
      end

      overlap_eoi_rev(input, state, current_state)
    end

    # A convenience method that returns the start state for a forward search
    # with the given anchored mode.
    def start_state(anchored : Anchored) : StateID
      start_state_forward_method(anchored)
    end

    # Returns true if the given state is a special state that is not a dead,
    # quit, match, start or accelerated state.
    def is_unknown_special_state?(id : StateID) : Bool
      is_special_state?(id) && !is_dead_state?(id) && !is_quit_state?(id) &&
        !is_match_state?(id) && !is_start_state?(id) && !is_accel_state?(id)
    end

    # Returns true if the given state is either a dead state or a quit state.
    def is_terminal_state?(id : StateID) : Bool
      is_dead_state?(id) || is_quit_state?(id)
    end

    # Returns true if the given state is either a match state or a start state.
    def is_non_terminal_special_state?(id : StateID) : Bool
      is_match_state?(id) || is_start_state?(id) || is_accel_state?(id)
    end

    # Returns the universal start state for the given anchored mode.
    #
    # A universal start state is a start state that works for all possible
    # start configurations. Not all DFAs have universal start states.
    def universal_start_state(anchored : Anchored) : StateID?
      nil
    end

    # Returns the prefilter for this automaton, if one exists.
    #
    # A prefilter is a fast way to skip over parts of the input that cannot
    # possibly match.
    def get_prefilter : Prefilter?
      nil
    end

    # Executes a forward search for overlapping matches and returns which
    # patterns matched.
    def try_which_overlapping_matches(slice : Bytes) : Array(PatternID) | MatchError
      result = try_search_overlapping_fwd(slice)
      return result if result.is_a?(MatchError)

      result
        .as(Array(Tuple(Int32, Array(PatternID))))
        .flat_map { |(_, patterns)| patterns }
        .uniq
    end

    private def overlap_eoi_fwd(input : Input, state : OverlappingState, current_state : StateID) : Nil | MatchError
      next_state_id = if trailing = input.haystack[input.end]?
                        next_state(current_state, trailing)
                      else
                        next_eoi_state(current_state)
                      end
      state.id = next_state_id
      if is_match_state?(next_state_id)
        state.mat = HalfMatch.new(match_pattern(next_state_id, 0), input.end < input.haystack.size ? input.end : input.haystack.size)
        state.next_match_index = 1
      elsif input.end < input.haystack.size && is_quit_state?(next_state_id)
        return MatchError.quit(input.haystack[input.end], input.end)
      end
      skip_empty_utf8_splits_overlapping_fwd(input, state)
    end

    private def skip_empty_utf8_splits_overlapping_fwd(input : Input, state : OverlappingState) : Nil | MatchError
      return nil unless has_empty? && is_utf8?

      half_match = state.get_match
      return nil unless half_match

      if input.get_anchored != Anchored::No
        state.mat = nil unless input.is_char_boundary(half_match.offset)
        return nil
      end

      while half_match && !input.is_char_boundary(half_match.offset)
        state.mat = nil
        result = try_search_overlapping_fwd(input, state)
        return result if result.is_a?(MatchError)
        half_match = state.get_match
      end
      nil
    end

    private def overlap_eoi_rev(input : Input, state : OverlappingState, current_state : StateID) : Nil | MatchError
      next_state_id = if input.start > 0
                        next_state(current_state, input.haystack[input.start - 1])
                      else
                        next_eoi_state(current_state)
                      end
      state.rev_eoi = true
      state.id = next_state_id
      if is_match_state?(next_state_id)
        state.mat = HalfMatch.new(match_pattern(next_state_id, 0), input.start)
        state.next_match_index = 1
      elsif input.start > 0 && is_quit_state?(next_state_id)
        return MatchError.quit(input.haystack[input.start - 1], input.start - 1)
      end
      skip_empty_utf8_splits_overlapping_rev(input, state)
    end

    private def skip_empty_utf8_splits_overlapping_rev(input : Input, state : OverlappingState) : Nil | MatchError
      return nil unless has_empty? && is_utf8?

      half_match = state.get_match
      return nil unless half_match

      if input.get_anchored != Anchored::No
        state.mat = nil unless input.is_char_boundary(half_match.offset)
        return nil
      end

      while half_match && !input.is_char_boundary(half_match.offset)
        state.mat = nil
        result = try_search_overlapping_rev(input, state)
        return result if result.is_a?(MatchError)
        half_match = state.get_match
      end
      nil
    end

    # A convenience method that checks if a match exists at the given position.
    def is_match_at(slice : Bytes, at : Int32) : Bool
      # Simple implementation: run a forward search starting at the given position
      # This is not optimal but works for the basic case
      subslice = slice[at..]?
      return false unless subslice
      result = try_search_fwd(subslice)
      case result
      when Tuple(Int32, Array(PatternID))
        true
      when MatchError
        false
      else
        false
      end
    end

    # Returns the earliest match found in the given slice.
    def find_earliest_match(slice : Bytes) : Tuple(Int32, Array(PatternID))? | MatchError
      current_state = start_state(StartConfig.new(nil, Anchored::No))
      case current_state
      when StartError
        return MatchError.quit(current_state.byte, 0) if current_state.is_a?(QuitStartError)
        return MatchError.unsupported_anchored(current_state.mode, current_state.pattern)
      when StateID
        idx = 0
        while idx < slice.size
          next_state = next_state(current_state, slice[idx])
          return MatchError.quit(slice[idx], idx) if is_quit_state?(next_state)
          break if is_dead_state?(next_state)

          current_state = next_state
          if is_match_state?(current_state)
            return {idx, Array.new(match_len(current_state)) { |i| match_pattern(current_state, i) }}
          end
          idx += 1
        end

        eoi_state = next_eoi_state(current_state)
        return MatchError.quit(0_u8, slice.size) if is_quit_state?(eoi_state)
        return {slice.size, Array.new(match_len(eoi_state)) { |i| match_pattern(eoi_state, i) }} if is_match_state?(eoi_state)
        nil
      end
    end
  end

  # Error type for start state computation failures.
  class StartError < Exception
    # Get the anchored mode (defaults to Anchored::No)
    def mode : Anchored
      Anchored::No
    end

    def pattern : PatternID?
      nil
    end

    # Get the byte (defaults to 0)
    def byte : UInt8
      0_u8
    end
  end

  # The automaton does not support the given anchored mode.
  class UnsupportedAnchoredStartError < StartError
    getter mode : Anchored
    getter pattern : PatternID?

    def initialize(@mode : Anchored, @pattern : PatternID? = nil)
      super("Unsupported anchored mode: #{@mode}")
    end
  end

  # The automaton encountered a quit byte while computing the start state.
  class QuitStartError < StartError
    getter byte : UInt8

    def initialize(@byte : UInt8)
      super("Quit byte: #{@byte}")
    end
  end

  # The automaton does not have a start state for the given configuration.
  class InvalidStartError < StartError
    def initialize
      super("Invalid start configuration")
    end
  end

  # Note: OverlappingState is defined in search.cr
end
