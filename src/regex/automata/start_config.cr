module Regex::Automata
  # Configuration for computing start states.
  #
  # This is used by the `Automaton.start_state` method to determine which
  # start state to use for a search.
  struct StartConfig
    # The byte immediately preceding the start of the search, if any.
    # If `nil`, the search is assumed to start at the beginning of the haystack.
    getter look_behind : UInt8?

    # Whether the search is anchored.
    getter anchored : Anchored
    # The pattern to anchor to when `Anchored::Pattern` is used.
    getter pattern : PatternID?

    # Create a new start configuration.
    def initialize(@look_behind : UInt8? = nil, @anchored : Anchored = Anchored::No, @pattern : PatternID? = nil)
    end

    # Create a start configuration from an input for a forward search.
    def self.from_input_forward(input : Input) : StartConfig
      look_behind = if input.start > 0 && input.start - 1 < input.haystack.size
                      input.haystack[input.start - 1]?
                    else
                      nil
                    end
      StartConfig.new(look_behind, input.anchored, input.pattern)
    end

    # Create a start configuration from an input for a reverse search.
    def self.from_input_reverse(input : Input) : StartConfig
      look_behind = if input.end < input.haystack.size
                      input.haystack[input.end]?
                    else
                      nil
                    end
      StartConfig.new(look_behind, input.anchored, input.pattern)
    end

    # Set the look-behind byte.
    def look_behind(byte : UInt8?) : StartConfig
      StartConfig.new(byte, @anchored, @pattern)
    end

    # Set the anchored mode.
    def anchored(mode : Anchored, pattern : PatternID? = nil) : StartConfig
      StartConfig.new(@look_behind, mode, pattern)
    end

    def get_look_behind : UInt8?
      @look_behind
    end

    def get_anchored : Anchored
      @anchored
    end
  end
end
