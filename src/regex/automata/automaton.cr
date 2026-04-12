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
      case result
      when StateID
        result
      when StartError
        case result
        when QuitStartError
          # For forward search, the quit byte is at position start-1
          offset = input.start > 0 ? input.start - 1 : 0
          MatchError.quit(result.byte, offset)
        when UnsupportedAnchoredStartError
          MatchError.unsupported_anchored(result.mode)
        else
          MatchError.generic("Unknown start error")
        end
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
      case result
      when StateID
        result
      when StartError
        case result
        when QuitStartError
          # For reverse search, the quit byte is at position end
          offset = input.end
          MatchError.quit(result.byte, offset)
        when UnsupportedAnchoredStartError
          MatchError.unsupported_anchored(result.mode)
        else
          MatchError.generic("Unknown start error")
        end
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

    # Executes a reverse search and returns a match if one is found.
    #
    # This is the core search routine for reverse searches.
    # Returns either a Tuple(match_position, pattern_ids) or nil if no match,
    # or a MatchError if an error occurred.
    abstract def try_search_rev(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError

    # Executes a forward overlapping search.
    #
    # This is used when searching for overlapping matches.
    abstract def try_search_overlapping_fwd(slice : Bytes) : Array(Tuple(Int32, Array(PatternID))) | MatchError

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
      case result
      when MatchError
        result
      when Array(Tuple(Int32, Array(PatternID)))
        result.flat_map { |(_, patterns)| patterns }.uniq
      else
        [] of PatternID
      end
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
      try_search_fwd(slice)
    end
  end

  # Error type for start state computation failures.
  class StartError < Exception
    # Get the anchored mode (defaults to Anchored::No)
    def mode : Anchored
      Anchored::No
    end

    # Get the byte (defaults to 0)
    def byte : UInt8
      0_u8
    end
  end

  # The automaton does not support the given anchored mode.
  class UnsupportedAnchoredStartError < StartError
    getter mode : Anchored

    def initialize(@mode : Anchored)
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
