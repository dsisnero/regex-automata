module Regex::Automata
  # Anchor mode for searches
  enum Anchored
    # The search is not anchored
    No
    # The search is anchored to the start of the haystack
    Yes
    # The search is anchored to a specific pattern
    Pattern
  end

  # A half match reported by a regex engine
  struct HalfMatch
    # The pattern ID
    getter pattern : PatternID
    # The offset of the match
    #
    # For forward searches, the offset is exclusive. For reverse searches,
    # the offset is inclusive.
    getter offset : Int32

    # Create a new half match from a pattern ID and a byte offset
    def initialize(@pattern : PatternID, @offset : Int32)
    end

    # Create a new half match from a pattern ID and a byte offset
    #
    # This is like `HalfMatch.new`, but accepts an `Int32` instead of a
    # `PatternID`.
    def self.must(pattern : Int32, offset : Int32) : HalfMatch
      new(PatternID.new(pattern), offset)
    end
  end

  # Input configuration for a search
  class Input
    getter haystack : Bytes
    getter span_start : Int32
    getter span_end : Int32
    getter anchored : Anchored
    getter earliest : Bool

    # Create a new search configuration for the given haystack
    def initialize(haystack : Bytes)
      @haystack = haystack
      @span_start = 0
      @span_end = haystack.size
      @anchored = Anchored::No
      @earliest = false
    end

    # Create a new search configuration for the given string
    def self.new(haystack : String) : Input
      new(haystack.to_slice)
    end

    # Create a new search configuration for the given bytes
    def self.new(haystack : Bytes) : Input
      new(haystack)
    end

    # Set the span for this search
    def span(range : Range(Int32, Int32)) : Input
      @span_start = range.begin
      @span_end = range.end
      self
    end

    # Set whether this search is anchored
    def anchored(@anchored : Anchored) : Input
      self
    end

    # Set whether to report the earliest match
    def earliest(@earliest : Bool) : Input
      self
    end
  end

  # State for overlapping searches
  class OverlappingState
    getter id : StateID
    getter match_index : Int32
    getter? next_state_index : Int32

    def initialize(@id : StateID = StateID.new(-1), @match_index : Int32 = 0, @next_state_index : Int32 = 0)
    end

    # Create a new overlapping state at the start
    def self.start : OverlappingState
      new
    end
  end
end
