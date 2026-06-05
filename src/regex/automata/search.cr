module Regex::Automata
  class Captures
  end

  # Anchor mode for searches
  enum Anchored
    # The search is not anchored
    No
    # The search is anchored to the start of the haystack
    Yes
    # The search is anchored to a specific pattern
    Pattern

    def is_anchored : Bool
      self != No
    end
  end

  # The match semantics to use for a regex
  enum MatchKind
    # Report all possible matches
    All
    # Report only the leftmost matches. When multiple leftmost matches exist,
    # report the match corresponding to the part of the regex that appears
    # first in the syntax.
    LeftmostFirst

    def continue_past_first_match : Bool
      self == All
    end
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

    def clone : Input
      Input.new(@haystack)
        .span(@span_start...@span_end)
        .anchored(@anchored, @pattern)
        .earliest(@earliest)
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

  # Shared iterator/search helper for non-overlapping match iteration.
  class Searcher
    getter input : Input

    @last_match_end : Int32?

    def initialize(input : Input)
      @input = input.clone
      @last_match_end = nil
    end

    def advance_half(&finder : Input -> HalfMatch? | MatchError) : HalfMatch?
      result = try_advance_half { |input| yield input }
      if result.is_a?(MatchError)
        raise "unexpected regex half find error: #{result}\n to handle find errors, use 'try' or 'search' methods"
      end
      result.as?(HalfMatch)
    end

    def advance(&finder : Input -> Match? | MatchError) : Match?
      result = try_advance { |input| yield input }
      if result.is_a?(MatchError)
        raise "unexpected regex find error: #{result}\n to handle find errors, use 'try' or 'search' methods"
      end
      result.as?(Match)
    end

    def try_advance_half(&finder : Input -> HalfMatch? | MatchError) : HalfMatch? | MatchError
      result = yield @input
      return result if result.is_a?(MatchError) || result.nil?

      match = result.as(HalfMatch)
      if @last_match_end == match.offset
        overlap = handle_overlapping_empty_half_match { |input| yield input }
        return overlap if overlap.is_a?(MatchError) || overlap.nil?
        match = overlap.as(HalfMatch)
      end

      @input.set_start(match.offset)
      @last_match_end = match.offset
      match
    end

    def try_advance(&finder : Input -> Match? | MatchError) : Match? | MatchError
      result = yield @input
      return result if result.is_a?(MatchError) || result.nil?

      match = result.as(Match)
      if match.empty? && @last_match_end == match.end
        overlap = handle_overlapping_empty_match(match) { |input| yield input }
        return overlap if overlap.is_a?(MatchError) || overlap.nil?
        match = overlap.as(Match)
      end

      @input.set_start(match.end)
      @last_match_end = match.end
      match
    end

    def into_half_matches_iter(&finder : Input -> HalfMatch? | MatchError) : TryHalfMatchesIter
      TryHalfMatchesIter.new(self, finder)
    end

    def into_matches_iter(&finder : Input -> Match? | MatchError) : TryMatchesIter
      TryMatchesIter.new(self, finder)
    end

    def into_captures_iter(caps : Captures, &finder : Input, Captures -> Nil | MatchError) : TryCapturesIter
      TryCapturesIter.new(self, caps, finder)
    end

    private def handle_overlapping_empty_half_match(&finder : Input -> HalfMatch? | MatchError) : HalfMatch? | MatchError
      @input.set_start(checked_add_one(@input.start))
      yield @input
    end

    private def handle_overlapping_empty_match(match : Match, &finder : Input -> Match? | MatchError) : Match? | MatchError
      raise "expected empty match" unless match.empty?

      @input.set_start(checked_add_one(@input.start))
      yield @input
    end

    private def checked_add_one(value : Int32) : Int32
      raise "search offset #{value} overflows Int32" if value == Int32::MAX

      value + 1
    end
  end

  class TryHalfMatchesIter
    @it : Searcher
    @finder : Proc(Input, HalfMatch? | MatchError)

    def initialize(@it : Searcher, @finder : Proc(Input, HalfMatch? | MatchError))
    end

    def infallible : HalfMatchesIter
      HalfMatchesIter.new(self)
    end

    def input : Input
      @it.input
    end

    def next
      result = @it.try_advance_half { |input| @finder.call(input) }
      result
    end
  end

  class HalfMatchesIter
    @it : TryHalfMatchesIter

    def initialize(@it : TryHalfMatchesIter)
    end

    def input : Input
      @it.input
    end

    include Enumerable(HalfMatch)

    def next
      result = @it.next
      return nil if result.nil?
      if result.is_a?(MatchError)
        raise "unexpected regex half find error: #{result}\n to handle find errors, use 'try' or 'search' methods"
      end

      result.as(HalfMatch)
    end

    def each(&block : HalfMatch ->)
      while match = self.next
        yield match
      end
    end
  end

  class TryMatchesIter
    @it : Searcher
    @finder : Proc(Input, Match? | MatchError)

    def initialize(@it : Searcher, @finder : Proc(Input, Match? | MatchError))
    end

    def infallible : MatchesIter
      MatchesIter.new(self)
    end

    def input : Input
      @it.input
    end

    def next
      result = @it.try_advance { |input| @finder.call(input) }
      result
    end
  end

  class MatchesIter
    @it : TryMatchesIter

    def initialize(@it : TryMatchesIter)
    end

    def input : Input
      @it.input
    end

    include Enumerable(Match)

    def next
      result = @it.next
      return nil if result.nil?
      if result.is_a?(MatchError)
        raise "unexpected regex find error: #{result}\n to handle find errors, use 'try' or 'search' methods"
      end

      result.as(Match)
    end

    def each(&block : Match ->)
      while match = self.next
        yield match
      end
    end
  end

  class TryCapturesIter
    @it : Searcher
    @caps : Captures
    @finder : Proc(Input, Captures, Nil | MatchError)

    def initialize(@it : Searcher, @caps : Captures, @finder : Proc(Input, Captures, Nil | MatchError))
    end

    def infallible : CapturesIter
      CapturesIter.new(self)
    end

    def next
      result = @it.try_advance do |input|
        finder_result = @finder.call(input, @caps)
        if finder_result.is_a?(MatchError)
          finder_result
        else
          @caps.get_match
        end
      end
      return nil if result.nil?
      return result if result.is_a?(MatchError)
      @caps.clone
    end
  end

  class CapturesIter
    @it : TryCapturesIter

    def initialize(@it : TryCapturesIter)
    end

    include Enumerable(Captures)

    def next
      result = @it.next
      return nil if result.nil?
      if result.is_a?(MatchError)
        raise "unexpected regex captures error: #{result}\n to handle find errors, use 'try' or 'search' methods"
      end

      result.as(Captures)
    end

    def each(&block : Captures ->)
      while captures = self.next
        yield captures
      end
    end
  end

  # State for overlapping searches
  class OverlappingState
    property mat : HalfMatch?
    property id : StateID?
    property at : Int32
    property next_match_index : Int32?
    property rev_eoi : Bool

    def initialize(@mat : HalfMatch? = nil, @id : StateID? = nil, @at : Int32 = 0, @next_match_index : Int32? = nil, @rev_eoi : Bool = false)
    end

    # Create a new overlapping state at the start
    def self.start : OverlappingState
      new
    end

    def get_match : HalfMatch?
      @mat
    end
  end

  # A set of matching pattern identifiers.
  class PatternSet
    @len : Int32
    @which : Array(Bool)

    def initialize(capacity : Int)
      if capacity < 0 || capacity > Int32::MAX
        raise ArgumentError.new("pattern set capacity exceeds Int32 limit")
      end
      @len = 0
      @which = Array(Bool).new(capacity, false)
    end

    def clear : Nil
      @len = 0
      @which.fill(false)
    end

    def contains(pid : PatternID) : Bool
      index = pid.to_i
      index >= 0 && index < capacity && @which[index]
    end

    def insert(pid : PatternID) : Bool
      result = try_insert(pid)
      raise result if result.is_a?(PatternSetInsertError)
      result
    end

    def try_insert(pid : PatternID) : Bool | PatternSetInsertError
      index = pid.to_i
      if index < 0 || index >= capacity
        return PatternSetInsertError.new(pid, capacity)
      end
      return false if @which[index]

      @len += 1
      @which[index] = true
      true
    end

    def remove(pid : PatternID) : Bool
      index = pid.to_i
      raise ArgumentError.new("pattern set should have sufficient capacity") if index < 0 || index >= capacity
      return false unless @which[index]

      @len -= 1
      @which[index] = false
      true
    end

    def is_empty : Bool
      @len == 0
    end

    def empty? : Bool
      is_empty
    end

    def is_full : Bool
      @len == capacity
    end

    def len : Int32
      @len
    end

    def capacity : Int32
      @which.size.to_i32
    end

    def iter : PatternSetIter
      PatternSetIter.new(@which)
    end
  end

  class PatternSetInsertError < Error
    getter attempted : PatternID
    getter capacity : Int32

    def initialize(@attempted : PatternID, @capacity : Int32)
      super("failed to insert pattern ID #{@attempted.to_i} into pattern set with insufficient capacity of #{@capacity}")
    end
  end

  # An iterator over all pattern identifiers in a PatternSet.
  class PatternSetIter
    include Enumerable(PatternID)

    @which : Array(Bool)
    @front : Int32
    @back : Int32

    def initialize(@which : Array(Bool))
      @front = 0
      @back = @which.size.to_i32 - 1
    end

    def next : PatternID?
      while @front <= @back
        index = @front
        @front += 1
        return PatternID.new(index) if @which[index]
      end
      nil
    end

    def next_back : PatternID?
      while @back >= @front
        index = @back
        @back -= 1
        return PatternID.new(index) if @which[index]
      end
      nil
    end

    def each(&block : PatternID ->)
      while pid = self.next
        yield pid
      end
    end
  end
end
