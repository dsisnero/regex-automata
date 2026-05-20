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

  # The match semantics to use for a regex
  enum MatchKind
    # Report all possible matches
    All
    # Report only the leftmost matches. When multiple leftmost matches exist,
    # report the match corresponding to the part of the regex that appears
    # first in the syntax.
    LeftmostFirst
  end

  # The kind of start states to support in a DFA
  enum StartKind
    # Support both anchored and unanchored searches
    Both
    # Support only unanchored searches
    Unanchored
    # Support only anchored searches
    Anchored
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

  # A complete match reported by a regex engine
  struct Match
    # The pattern ID
    getter pattern : PatternID
    # The start position of the match (inclusive)
    getter start : Int32
    # The end position of the match (exclusive)
    getter end : Int32

    # Create a new match from a pattern ID and a span
    def initialize(@pattern : PatternID, @start : Int32, @end : Int32)
      raise "invalid match span: end < start" if @end < @start
    end

    # Create a new match from a pattern ID and a range
    def initialize(@pattern : PatternID, range : Range(Int32, Int32))
      @start = range.begin
      @end = range.end
      raise "invalid match span: end < start" if @end < @start
    end

    # Create a new match from a pattern ID and a span
    #
    # This is like `Match.new`, but accepts an `Int32` instead of a
    # `PatternID`.
    def self.must(pattern : Int32, start : Int32, _end : Int32) : Match
      new(PatternID.new(pattern), start, _end)
    end

    # Create a new match from a pattern ID and a range
    #
    # This is like `Match.new`, but accepts an `Int32` instead of a
    # `PatternID`.
    def self.must(pattern : Int32, range : Range(Int32, Int32)) : Match
      new(PatternID.new(pattern), range)
    end

    # Returns the span as a range
    def span : Range(Int32, Int32)
      @start...@end
    end

    # Returns the length of the match
    def length : Int32
      @end - @start
    end

    # Returns true if the match is empty
    def empty? : Bool
      @start == @end
    end
  end

  # A half-open byte span.
  struct Span
    getter start : Int32
    getter end : Int32

    def initialize(@start : Int32, @end : Int32)
    end

    def range : Range(Int32, Int32)
      @start...@end
    end

    def empty? : Bool
      @start >= @end
    end

    def length : Int32
      Math.max(@end - @start, 0)
    end

    def contains?(offset : Int32) : Bool
      !empty? && @start <= offset && offset < @end
    end

    def offset(amount : Int32) : Span
      Span.new(@start + amount, @end + amount)
    end
  end

  # Input configuration for a search
  class Input
    getter haystack : Bytes
    getter anchored : Anchored
    getter pattern : PatternID?
    getter earliest : Bool
    getter span_start : Int32
    getter span_end : Int32

    # Create a new search configuration for the given haystack
    def initialize(haystack : Bytes)
      @haystack = haystack
      @anchored = Anchored::No
      @pattern = nil
      @earliest = false
      @span_start = 0
      @span_end = haystack.size
    end

    # Create a new search configuration for the given string
    def initialize(haystack : String)
      @haystack = haystack.to_slice
      @anchored = Anchored::No
      @pattern = nil
      @earliest = false
      @span_start = 0
      @span_end = @haystack.size
    end

    # Set the span for this search
    def span(range : Range(Int32, Int32)) : Input
      set_span(range)
      self
    end

    # Set the range for this search using Crystal range semantics.
    def range(range : Range(Int32, Int32)) : Input
      set_range(range)
      self
    end

    # Set whether this search is anchored
    def anchored(mode : Anchored, pattern : PatternID? = nil) : Input
      set_anchored(mode, pattern)
      self
    end

    def anchored_pattern(pattern : PatternID) : Input
      @anchored = Anchored::Pattern
      @pattern = pattern
      self
    end

    # Set whether to report the earliest match
    def earliest(@earliest : Bool) : Input
      self
    end

    def set_span(span : Span) : Nil
      validate_span(span)
      @span_start = span.start
      @span_end = span.end
    end

    def set_span(range : Range(Int32, Int32)) : Nil
      set_span(Span.new(range.begin, range.end))
    end

    def set_range(range : Range(Int32, Int32)) : Nil
      end_offset = range.excludes_end? ? range.end : checked_add_one(range.end)
      set_span(Span.new(range.begin, end_offset))
    end

    def set_start(start : Int32) : Nil
      set_span(Span.new(start, @span_end))
    end

    def set_end(finish : Int32) : Nil
      set_span(Span.new(@span_start, finish))
    end

    def set_anchored(mode : Anchored, pattern : PatternID? = nil) : Nil
      @anchored = mode
      @pattern = pattern
    end

    def set_earliest(@earliest : Bool) : Nil
    end

    # Get the start position of the search
    def start : Int32
      @span_start
    end

    # Get the end position of the search
    def end : Int32
      @span_end
    end

    def get_span : Span
      Span.new(@span_start, @span_end)
    end

    def get_range : Range(Int32, Int32)
      get_span.range
    end

    def get_anchored : Anchored
      @anchored
    end

    def get_earliest : Bool
      @earliest
    end

    def is_done : Bool
      @span_start > @span_end
    end

    # Assumes valid UTF-8 input, like upstream.
    def is_char_boundary(offset : Int32) : Bool
      return false if offset < 0 || offset > @haystack.size
      return true if offset == 0 || offset == @haystack.size

      byte = @haystack[offset]
      byte < 0x80 || byte >= 0xC0
    end

    private def validate_span(span : Span) : Nil
      haystack_size = @haystack.size
      return if span.end <= haystack_size && span.start <= span.end + 1

      raise ArgumentError.new("invalid span #{span.start}...#{span.end} for haystack of length #{haystack_size}")
    end

    private def checked_add_one(value : Int32) : Int32
      raise ArgumentError.new("range end #{value} overflows Int32") if value == Int32::MAX

      value + 1
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
