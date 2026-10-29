require "./utf8_sequences"
require "./look"
require "./captures"
require "./types"
require "./byte_classes"
require "./sparse_set"
require "./escape"

module Regex::Automata::NFA
  alias StateID = Regex::Automata::StateID
  alias PatternID = Regex::Automata::PatternID

  # Errors raised while compiling a Thompson NFA. This preserves the
  # distinction Rust exposes between syntax, capture, Unicode-word-boundary,
  # size-limit and reverse-capture failures while remaining a subtype of the
  # port's public BuildError.
  class BuildError < ::Regex::Automata::BuildError
    enum Kind
      Syntax
      Captures
      Word
      TooManyPatterns
      TooManyStates
      ExceededSizeLimit
      InvalidCaptureIndex
      UnsupportedCaptures
    end

    getter kind : Kind
    getter source : Exception?

    def initialize(@kind : Kind, message : String, @source : Exception? = nil, size_limit_exceeded : Bool = false, size_limit : Int64? = nil)
      super(message, size_limit_exceeded: size_limit_exceeded, size_limit: size_limit)
    end

    def self.syntax(error : Exception) : BuildError
      new(Kind::Syntax, "error parsing regex", error)
    end

    def self.captures(error : Exception) : BuildError
      new(Kind::Captures, "error with capture groups", error)
    end

    def self.word(_error : Exception) : BuildError
      new(Kind::Word, "NFA contains Unicode word boundary")
    end

    def self.too_many_patterns(given : Int64) : BuildError
      new(Kind::TooManyPatterns, "attempted to compile #{given} patterns, which exceeds the limit of #{PatternID::LIMIT}")
    end

    def self.too_many_states(given : Int64) : BuildError
      new(Kind::TooManyStates, "attempted to compile #{given} NFA states, which exceeds the limit of #{StateID::LIMIT}")
    end

    def self.exceeded_size_limit(limit : Int64) : BuildError
      new(Kind::ExceededSizeLimit, "heap usage during NFA compilation exceeded limit of #{limit}", size_limit_exceeded: true, size_limit: limit)
    end

    def self.invalid_capture_index(index : UInt32) : BuildError
      new(Kind::InvalidCaptureIndex, "capture group index #{index} is invalid (too big or discontinuous)")
    end

    def self.unsupported_captures : BuildError
      new(Kind::UnsupportedCaptures, "currently captures must be disabled when compiling a reverse NFA")
    end
  end

  enum WhichCaptures
    All
    Implicit
    None

    def is_none : Bool
      self == None
    end

    def is_any : Bool
      !is_none
    end
  end

  class PatternIter
    include Iterator(PatternID)

    def initialize(@limit : Int32)
      @next_id = 0
    end

    def next
      return stop if @next_id >= @limit

      value = PatternID.new(@next_id)
      @next_id += 1
      value
    end
  end

  # A transition between NFA states
  struct Transition
    # Range of bytes that trigger this transition
    getter start : UInt8
    getter end : UInt8
    # Target state ID
    getter next : StateID

    def initialize(@start : UInt8, @end : UInt8, @next : StateID)
    end

    def inspect(io : IO) : Nil
      Regex::Automata::DebugByte.new(@start).inspect(io)
      if @start != @end
        io << '-'
        Regex::Automata::DebugByte.new(@end).inspect(io)
      end
      io << " => " << @next.to_i
    end

    # Check if byte is in range
    def matches?(byte : UInt8) : Bool
      byte >= @start && byte <= @end
    end

    def matches_byte(byte : UInt8) : Bool
      matches?(byte)
    end

    def matches_unit(unit : Regex::Automata::Unit) : Bool
      unit.as_u8.try { |byte| matches?(byte) } || false
    end

    def matches(haystack : Bytes, at : Int32) : Bool
      return false if at < 0 || at >= haystack.size

      matches?(haystack[at])
    end
  end

  # Different types of NFA states
  alias State = ByteRange | Sparse | Dense | Look | Union | BinaryUnion | Capture | Match | Fail | Empty

  # Single byte range transition
  struct ByteRange
    getter trans : Transition

    def initialize(@trans : Transition)
    end

    def inspect(io : IO) : Nil
      @trans.inspect(io)
    end

    def is_epsilon : Bool
      false
    end
  end

  # Sparse transitions (multiple non-overlapping ranges)
  struct Sparse
    getter transitions : Array(Transition)

    def initialize(@transitions : Array(Transition))
    end

    def inspect(io : IO) : Nil
      io << "sparse("
      @transitions.each_with_index do |trans, index|
        io << ", " if index > 0
        trans.inspect(io)
      end
      io << ')'
    end

    def matches_byte(byte : UInt8) : StateID?
      @transitions.each do |trans|
        break if trans.start > byte
        return trans.next if trans.matches_byte(byte)
      end
      nil
    end

    def matches_unit(unit : Regex::Automata::Unit) : StateID?
      unit.as_u8.try { |byte| matches_byte(byte) }
    end

    def matches(haystack : Bytes, at : Int32) : StateID?
      return nil if at < 0 || at >= haystack.size

      matches_byte(haystack[at])
    end

    def is_epsilon : Bool
      false
    end
  end

  # Pinned Rust retains this representation and its search branches, but does
  # not currently convert compiler-generated sparse states to dense states.
  struct Dense
    getter transitions : Array(StateID)

    def initialize(@transitions : Array(StateID))
    end

    def inspect(io : IO) : Nil
      io << "dense("
      iter.each_with_index do |trans, index|
        io << ", " if index > 0
        trans.inspect(io)
      end
      io << ')'
    end

    def matches_byte(byte : UInt8) : StateID?
      target = @transitions[byte.to_i]
      target == StateID::ZERO ? nil : target
    end

    def matches_unit(unit : Regex::Automata::Unit) : StateID?
      unit.as_u8.try { |byte| matches_byte(byte) }
    end

    def matches(haystack : Bytes, at : Int32) : StateID?
      return nil if at < 0 || at >= haystack.size

      matches_byte(haystack[at])
    end

    def iter : Array(Transition)
      result = [] of Transition
      @transitions.each_with_index do |target, byte|
        next if target == StateID::ZERO

        result << Transition.new(byte.to_u8, byte.to_u8, target)
      end
      result
    end

    def is_epsilon : Bool
      false
    end
  end

  # Look-around assertion (word boundary, ^, $, etc.)
  struct Look
    enum Kind
      StartLF                # ^ with LF line mode
      EndLF                  # $ with LF line mode
      StartCRLF              # ^ with CRLF line mode
      EndCRLF                # $ with CRLF line mode
      WordBoundaryAscii      # (?-u:\b)
      NonWordBoundaryAscii   # (?-u:\B)
      WordBoundaryUnicode    # \b
      NonWordBoundaryUnicode # \B
      WordStartAscii
      WordEndAscii
      WordStartUnicode
      WordEndUnicode
      WordStartHalfAscii
      WordEndHalfAscii
      WordStartHalfUnicode
      WordEndHalfUnicode
      StartText          # \A
      EndText            # \z
      EndTextWithNewline # \Z
    end

    getter kind : Kind
    getter next : StateID

    def initialize(@kind : Kind, @next : StateID)
    end

    def inspect(io : IO) : Nil
      name = case @kind
             when Kind::WordBoundaryAscii                 then "WordAscii"
             when Kind::NonWordBoundaryAscii              then "WordAsciiNegate"
             when Kind::WordBoundaryUnicode               then "WordUnicode"
             when Kind::NonWordBoundaryUnicode            then "WordUnicodeNegate"
             when Kind::StartText                         then "Start"
             when Kind::EndText, Kind::EndTextWithNewline then "End"
             else                                              @kind.to_s
             end
      io << name << " => " << @next.to_i
    end

    def is_epsilon : Bool
      true
    end
  end

  # Union/alternation (epsilon transitions to multiple states)
  struct Union
    getter alternates : Array(StateID)

    def initialize(@alternates : Array(StateID))
    end

    def inspect(io : IO) : Nil
      io << "union("
      @alternates.each_with_index do |sid, index|
        io << ", " if index > 0
        io << sid.to_i
      end
      io << ')'
    end

    def is_epsilon : Bool
      true
    end
  end

  # Binary union (common case of 2 alternates)
  struct BinaryUnion
    getter alt1 : StateID
    getter alt2 : StateID

    def initialize(@alt1 : StateID, @alt2 : StateID)
    end

    def inspect(io : IO) : Nil
      io << "binary-union(" << @alt1.to_i << ", " << @alt2.to_i << ')'
    end

    def is_epsilon : Bool
      true
    end
  end

  # Capture state (for capturing groups)
  struct Capture
    getter next : StateID
    getter pattern_id : PatternID
    getter group_index : Int32
    getter slot : Int32

    def initialize(@next : StateID, @pattern_id : PatternID, @group_index : Int32, @slot : Int32)
    end

    def inspect(io : IO) : Nil
      io << "capture(pid=" << @pattern_id.to_i << ", group=" << @group_index << ", slot=" << @slot << ") => " << @next.to_i
    end

    def is_epsilon : Bool
      true
    end
  end

  # Match state (accepting state for a pattern)
  struct Match
    getter pattern_id : PatternID
    getter next : StateID?

    def initialize(@pattern_id : PatternID, @next : StateID? = nil)
    end

    def inspect(io : IO) : Nil
      io << "MATCH(" << @pattern_id.to_i << ')'
    end

    def is_epsilon : Bool
      false
    end
  end

  # Fail state (no transitions)
  struct Fail
    def initialize
    end

    def inspect(io : IO) : Nil
      io << "FAIL"
    end

    def is_epsilon : Bool
      false
    end
  end

  # Empty state (epsilon transition)
  struct Empty
    getter next : StateID

    def initialize(@next : StateID)
    end

    def inspect(io : IO) : Nil
      io << "empty => " << @next.to_i
    end

    def is_epsilon : Bool
      true
    end
  end

  # Reference to a sub-NFA (start and end states)
  struct ThompsonRef
    getter start : StateID
    getter end : StateID

    def initialize(@start : StateID, @end : StateID)
    end
  end

  private struct Utf8LastTransition
    getter start : UInt8
    getter end : UInt8

    def initialize(@start : UInt8, @end : UInt8)
    end
  end

  private class Utf8Node
    getter trans : Array(Transition)
    property last : Utf8LastTransition?

    def initialize(@trans : Array(Transition) = [] of Transition, @last : Utf8LastTransition? = nil)
    end

    def set_last_transition(next_id : StateID) : Nil
      if last = @last
        @trans << Transition.new(last.start, last.end, next_id)
        @last = nil
      end
    end
  end

  # These bounded maps are caches, not general maps: a collision may evict an
  # entry, which only makes the generated UTF-8 NFA less compact. Keeping a
  # fixed slot count matches Rust's compilation-time/memory trade-off.
  UTF8_MAP_PRIME =          1_099_511_628_211_u64
  UTF8_MAP_INIT  = 14_695_981_039_346_656_037_u64

  private struct Utf8BoundedEntry
    property version : UInt16
    property key : Array(Transition)
    property val : StateID

    def initialize(@version : UInt16 = 0_u16, @key : Array(Transition) = [] of Transition, @val : StateID = StateID.new(0))
    end
  end

  private class Utf8BoundedMap
    @version : UInt16
    @capacity : Int32
    @map : Array(Utf8BoundedEntry)

    def initialize(@capacity : Int32)
      raise ArgumentError.new("UTF-8 bounded map capacity must be positive") unless @capacity > 0

      @version = 0_u16
      @map = [] of Utf8BoundedEntry
    end

    def clear : Nil
      if @map.empty?
        @map = Array.new(@capacity) { Utf8BoundedEntry.new }
      else
        @version &+= 1_u16
        @map = Array.new(@capacity) { Utf8BoundedEntry.new } if @version == 0_u16
      end
    end

    def hash(key : Array(Transition)) : Int32
      hash = UTF8_MAP_INIT
      key.each do |transition|
        hash = (hash ^ transition.start.to_u64) &* UTF8_MAP_PRIME
        hash = (hash ^ transition.end.to_u64) &* UTF8_MAP_PRIME
        hash = (hash ^ transition.next.as_u64) &* UTF8_MAP_PRIME
      end
      (hash % @map.size.to_u64).to_i32
    end

    def get(key : Array(Transition), hash : Int32) : StateID?
      entry = @map[hash]
      return nil unless entry.version == @version
      return nil unless entry.key == key

      entry.val
    end

    def set(key : Array(Transition), hash : Int32, state_id : StateID) : Nil
      @map[hash] = Utf8BoundedEntry.new(@version, key, state_id)
    end
  end

  private struct Utf8SuffixKey
    getter from : StateID
    getter start : UInt8
    getter end : UInt8

    def initialize(@from : StateID, @start : UInt8, @end : UInt8)
    end
  end

  private struct Utf8SuffixEntry
    property version : UInt16
    property key : Utf8SuffixKey
    property val : StateID

    def initialize(@version : UInt16 = 0_u16, @key : Utf8SuffixKey = Utf8SuffixKey.new(StateID.new(0), 0_u8, 0_u8), @val : StateID = StateID.new(0))
    end
  end

  private class Utf8SuffixMap
    @version : UInt16
    @capacity : Int32
    @map : Array(Utf8SuffixEntry)

    def initialize(@capacity : Int32)
      raise ArgumentError.new("UTF-8 suffix map capacity must be positive") unless @capacity > 0

      @version = 0_u16
      @map = [] of Utf8SuffixEntry
    end

    def clear : Nil
      if @map.empty?
        @map = Array.new(@capacity) { Utf8SuffixEntry.new }
      else
        @version &+= 1_u16
        @map = Array.new(@capacity) { Utf8SuffixEntry.new } if @version == 0_u16
      end
    end

    def hash(key : Utf8SuffixKey) : Int32
      hash = UTF8_MAP_INIT
      hash = (hash ^ key.from.as_u64) &* UTF8_MAP_PRIME
      hash = (hash ^ key.start.to_u64) &* UTF8_MAP_PRIME
      hash = (hash ^ key.end.to_u64) &* UTF8_MAP_PRIME
      (hash % @map.size.to_u64).to_i32
    end

    def get(key : Utf8SuffixKey, hash : Int32) : StateID?
      entry = @map[hash]
      return nil unless entry.version == @version
      return nil unless entry.key == key

      entry.val
    end

    def set(key : Utf8SuffixKey, hash : Int32, state_id : StateID) : Nil
      @map[hash] = Utf8SuffixEntry.new(@version, key, state_id)
    end
  end

  private class Utf8CompilerState
    getter compiled : Utf8BoundedMap
    getter uncompiled : Array(Utf8Node)

    def initialize
      @compiled = Utf8BoundedMap.new(10_000)
      @uncompiled = [] of Utf8Node
    end

    def clear : Nil
      @compiled.clear
      @uncompiled.clear
    end
  end

  private enum RangeTrieSplitKind
    Old
    New
    Both
  end

  private struct RangeTrieSplitRange
    getter kind : RangeTrieSplitKind
    getter range : ::Regex::Automata::Utf8Range

    def initialize(@kind : RangeTrieSplitKind, @range : ::Regex::Automata::Utf8Range)
    end
  end

  private struct RangeTrieTransition
    getter range : ::Regex::Automata::Utf8Range
    getter next_id : Int32

    def initialize(@range : ::Regex::Automata::Utf8Range, @next_id : Int32)
    end

    def inspect(io : IO) : Nil
      io << @range.start.to_s(16).upcase.rjust(2, '0')
      if @range.start != @range.end
        io << '-' << @range.end.to_s(16).upcase.rjust(2, '0')
      end
      io << " => " << @next_id.to_s(16).upcase.rjust(2, '0')
    end
  end

  private class RangeTrieState
    getter transitions : Array(RangeTrieTransition)

    def initialize
      @transitions = [] of RangeTrieTransition
    end

    def clear : Nil
      @transitions.clear
    end

    def inspect(io : IO) : Nil
      @transitions.each_with_index do |transition, index|
        io << ", " if index > 0
        transition.inspect(io)
      end
    end

    def find(range : ::Regex::Automata::Utf8Range) : Int32
      left = 0
      right = @transitions.size
      while left < right
        mid = (left + right) // 2
        if range.start <= @transitions[mid].range.end
          right = mid
        else
          left = mid + 1
        end
      end
      left.to_i32
    end
  end

  private struct RangeTrieSplit
    include Enumerable(RangeTrieSplitRange)

    @partitions : StaticArray(RangeTrieSplitRange, 3)
    @length : Int32

    def initialize(@partitions : StaticArray(RangeTrieSplitRange, 3), @length : Int32)
    end

    def size : Int32
      @length
    end

    def each(&block : RangeTrieSplitRange ->) : Nil
      @length.times { |index| yield @partitions[index] }
    end

    private def self.range(start_byte : UInt8, end_byte : UInt8) : ::Regex::Automata::Utf8Range
      ::Regex::Automata::Utf8Range.new(start_byte, end_byte)
    end

    private def self.old(start_byte : UInt8, end_byte : UInt8) : RangeTrieSplitRange
      RangeTrieSplitRange.new(RangeTrieSplitKind::Old, range(start_byte, end_byte))
    end

    private def self.new_part(start_byte : UInt8, end_byte : UInt8) : RangeTrieSplitRange
      RangeTrieSplitRange.new(RangeTrieSplitKind::New, range(start_byte, end_byte))
    end

    private def self.both(start_byte : UInt8, end_byte : UInt8) : RangeTrieSplitRange
      RangeTrieSplitRange.new(RangeTrieSplitKind::Both, range(start_byte, end_byte))
    end

    private def self.parts1(first : RangeTrieSplitRange) : RangeTrieSplit
      filler = old(0_u8, 0_u8)
      new(StaticArray(RangeTrieSplitRange, 3).new { |index| index == 0 ? first : filler }, 1)
    end

    private def self.parts2(first : RangeTrieSplitRange, second : RangeTrieSplitRange) : RangeTrieSplit
      filler = old(0_u8, 0_u8)
      new(StaticArray(RangeTrieSplitRange, 3).new { |index| index == 0 ? first : index == 1 ? second : filler }, 2)
    end

    private def self.parts3(first : RangeTrieSplitRange, second : RangeTrieSplitRange, third : RangeTrieSplitRange) : RangeTrieSplit
      new(StaticArray(RangeTrieSplitRange, 3).new { |index| index == 0 ? first : index == 1 ? second : third }, 3)
    end

    def self.build(old_range : ::Regex::Automata::Utf8Range, new_range : ::Regex::Automata::Utf8Range) : RangeTrieSplit?
      a = old_range.start
      b = old_range.end
      x = new_range.start
      y = new_range.end

      if b < x || y < a
        nil
      elsif a == x && b == y
        parts1(both(a, b))
      elsif a == x && b < y
        parts2(both(a, b), new_part((b + 1).to_u8, y))
      elsif b == y && a > x
        parts2(new_part(x, (a - 1).to_u8), both(a, b))
      elsif x == a && y < b
        parts2(both(x, y), old((y + 1).to_u8, b))
      elsif y == b && x > a
        parts2(old(a, (x - 1).to_u8), both(x, y))
      elsif a > x && b < y
        parts3(new_part(x, (a - 1).to_u8), both(a, b), new_part((b + 1).to_u8, y))
      elsif x > a && y < b
        parts3(old(a, (x - 1).to_u8), both(x, y), old((y + 1).to_u8, b))
      elsif b == x && a < y
        parts3(old(a, (b - 1).to_u8), both(b, b), new_part((b + 1).to_u8, y))
      elsif y == a && x < b
        parts3(new_part(x, (y - 1).to_u8), both(y, y), old((y + 1).to_u8, b))
      elsif b > x && b < y
        parts3(old(a, (x - 1).to_u8), both(x, b), new_part((b + 1).to_u8, y))
      elsif y > a && y < b
        parts3(new_part(x, (a - 1).to_u8), both(a, y), old((y + 1).to_u8, b))
      else
        raise "unreachable range trie split"
      end
    end
  end

  # Rust's NextInsert stores at most four UTF-8 ranges inline. Keeping the
  # pending suffix in a StaticArray avoids allocating a slice at each branch.
  private struct RangeTrieNextInsert
    getter state_id : Int32

    @ranges : StaticArray(::Regex::Automata::Utf8Range, 4)
    @length : Int32

    def initialize(@state_id : Int32, ranges : Array(::Regex::Automata::Utf8Range))
      @length = ranges.size.to_i32
      raise "expected 1-4 UTF-8 ranges" unless @length >= 1 && @length <= 4

      zero = ::Regex::Automata::Utf8Range.new(0_u8, 0_u8)
      @ranges = StaticArray(::Regex::Automata::Utf8Range, 4).new { |index| index < @length ? ranges[index] : zero }
    end

    def initialize(@state_id : Int32, @ranges : StaticArray(::Regex::Automata::Utf8Range, 4), @length : Int32)
    end

    def first : ::Regex::Automata::Utf8Range
      @ranges[0]
    end

    def has_rest? : Bool
      @length > 1
    end

    def next_for(state_id : Int32) : RangeTrieNextInsert
      raise "expected remaining UTF-8 ranges" unless has_rest?

      zero = ::Regex::Automata::Utf8Range.new(0_u8, 0_u8)
      shifted = StaticArray(::Regex::Automata::Utf8Range, 4).new do |index|
        index + 1 < @length ? @ranges[index + 1] : zero
      end
      RangeTrieNextInsert.new(state_id, shifted, @length - 1)
    end
  end

  private class RangeTrie
    FINAL = 0
    ROOT  = 1

    @states : Array(RangeTrieState)
    @free : Array(RangeTrieState)
    @insert_stack : Array(RangeTrieNextInsert)
    @dupe_stack : Array(Tuple(Int32, Int32))
    @iter_stack : Array(Tuple(Int32, Int32))
    @iter_ranges : Array(::Regex::Automata::Utf8Range)

    def initialize
      @states = [] of RangeTrieState
      @free = [] of RangeTrieState
      @insert_stack = [] of RangeTrieNextInsert
      @dupe_stack = [] of Tuple(Int32, Int32)
      @iter_stack = [] of Tuple(Int32, Int32)
      @iter_ranges = [] of ::Regex::Automata::Utf8Range
      clear
    end

    def clear : Nil
      @free.concat(@states)
      @states.clear
      add_empty # final
      add_empty # root
    end

    def inspect(io : IO) : Nil
      io << '\n'
      @states.each_with_index do |state, index|
        io << (index == FINAL ? '*' : ' ')
        io << index.to_s.rjust(6, '0') << ": "
        state.inspect(io)
        io << '\n'
      end
    end

    def insert(ranges : Array(::Regex::Automata::Utf8Range)) : Nil
      raise "expected non-empty UTF-8 ranges" if ranges.empty?
      raise "expected at most four UTF-8 ranges" if ranges.size > 4

      stack = @insert_stack
      stack.clear
      stack << RangeTrieNextInsert.new(ROOT, ranges)
      until stack.empty?
        pending = stack.pop
        state_id = pending.state_id
        new_range = pending.first
        index = state(state_id).find(new_range)

        if index == state(state_id).transitions.size
          add_transition(state_id, new_range, push_pending(stack, pending))
          next
        end

        loop do
          old_transition = state(state_id).transitions[index]
          if split = RangeTrieSplit.build(old_transition.range, new_range)
            parts = split
            if parts.size == 1
              stack << pending.next_for(old_transition.next_id) if pending.has_rest?
              break
            end

            first = true
            repeat_overlap = false
            overlap_range = new_range

            parts.each_with_index do |part, part_index|
              target_id = nil.as(Int32?)
              case part.kind
              when RangeTrieSplitKind::Old
                target_id = duplicate(old_transition.next_id)
              when RangeTrieSplitKind::New
                transitions = state(state_id).transitions
                if part_index + 1 == parts.size &&
                   index < transitions.size &&
                   intersects(part.range, transitions[index].range)
                  overlap_range = part.range
                  repeat_overlap = true
                  break
                end
                target_id = push_pending(stack, pending)
              when RangeTrieSplitKind::Both
                stack << pending.next_for(old_transition.next_id) if pending.has_rest?
                target_id = old_transition.next_id
              end
              next unless target_id
              target = target_id.not_nil!

              if first
                set_transition_at(index, state_id, part.range, target)
                first = false
              else
                add_transition_at(index, state_id, part.range, target)
              end
              index += 1
            end

            if repeat_overlap
              new_range = overlap_range
              next
            end
            break
          else
            add_transition_at(index, state_id, new_range, push_pending(stack, pending))
            break
          end
        end
      end
    end

    def each(&block : Array(::Regex::Automata::Utf8Range) ->) : Nil
      stack = @iter_stack
      ranges = @iter_ranges
      stack.clear
      ranges.clear
      stack << {ROOT, 0}

      until stack.empty?
        state_id, transition_index = stack.pop
        loop do
          transitions = state(state_id).transitions
          if transition_index >= transitions.size
            ranges.pop?
            break
          end

          transition = transitions[transition_index]
          ranges << transition.range
          if transition.next_id == FINAL
            yield ranges
            ranges.pop
            transition_index += 1
          else
            stack << {state_id, transition_index + 1}
            state_id = transition.next_id
            transition_index = 0
          end
        end
      end
    end

    private def push_pending(stack : Array(RangeTrieNextInsert), pending : RangeTrieNextInsert) : Int32
      if !pending.has_rest?
        FINAL
      else
        next_id = add_empty
        stack << pending.next_for(next_id)
        next_id
      end
    end

    private def duplicate(old_id : Int32) : Int32
      return FINAL if old_id == FINAL

      new_id = add_empty
      stack = @dupe_stack
      stack.clear
      stack << {old_id, new_id}
      until stack.empty?
        current_old, current_new = stack.pop
        state(current_old).transitions.each do |transition|
          if transition.next_id == FINAL
            add_transition(current_new, transition.range, FINAL)
          else
            child_new = add_empty
            add_transition(current_new, transition.range, child_new)
            stack << {transition.next_id, child_new}
          end
        end
      end
      new_id
    end

    private def add_empty : Int32
      state = @free.pop? || RangeTrieState.new
      state.clear
      @states << state
      (@states.size - 1).to_i32
    end

    private def add_transition(from_id : Int32, range : ::Regex::Automata::Utf8Range, next_id : Int32) : Nil
      state(from_id).transitions << RangeTrieTransition.new(range, next_id)
    end

    private def add_transition_at(index : Int32, from_id : Int32, range : ::Regex::Automata::Utf8Range, next_id : Int32) : Nil
      state(from_id).transitions.insert(index, RangeTrieTransition.new(range, next_id))
    end

    private def set_transition_at(index : Int32, from_id : Int32, range : ::Regex::Automata::Utf8Range, next_id : Int32) : Nil
      state(from_id).transitions[index] = RangeTrieTransition.new(range, next_id)
    end

    private def state(id : Int32) : RangeTrieState
      @states[id]
    end

    private def intersects(left : ::Regex::Automata::Utf8Range, right : ::Regex::Automata::Utf8Range) : Bool
      !(left.end < right.start || right.end < left.start)
    end
  end

  private class Utf8Compiler
    @state : Utf8CompilerState
    getter target : StateID

    def initialize(@builder : Builder)
      @state = Utf8CompilerState.new
      @target = @builder.add_state(Empty.new(StateID.new(0)))
      @state.clear
      add_empty
    end

    def add(ranges : Array(::Regex::Automata::Utf8Range)) : Nil
      prefix_len = 0
      max = Math.min(ranges.size, @state.uncompiled.size)
      while prefix_len < max
        node = @state.uncompiled[prefix_len]
        last = node.last
        break unless last && last.start == ranges[prefix_len].start && last.end == ranges[prefix_len].end
        prefix_len += 1
      end
      raise "expected non-empty UTF-8 suffix" unless prefix_len < ranges.size

      compile_from(prefix_len)
      add_suffix(ranges[prefix_len..])
    end

    def finish : ThompsonRef
      compile_from(0)
      start_id = compile(pop_root)
      ThompsonRef.new(start_id, @target)
    end

    private def compile_from(from : Int32) : Nil
      next_id = @target
      while from + 1 < @state.uncompiled.size
        next_id = compile(pop_freeze(next_id))
      end
      top_last_freeze(next_id)
    end

    private def compile(node : Array(Transition)) : StateID
      hash = @state.compiled.hash(node)
      if compiled_id = @state.compiled.get(node, hash)
        return compiled_id
      end

      state = if node.size == 1
                ByteRange.new(node.first).as(State)
              else
                Sparse.new(node).as(State)
              end
      id = @builder.add_state(state)
      @state.compiled.set(node, hash, id)
      id
    end

    private def add_suffix(ranges : Array(::Regex::Automata::Utf8Range)) : Nil
      raise "expected non-empty UTF-8 suffix" if ranges.empty?

      last_index = @state.uncompiled.size - 1
      raise "expected pending transition slot" if @state.uncompiled[last_index].last
      @state.uncompiled[last_index].last = Utf8LastTransition.new(ranges[0].start, ranges[0].end)
      ranges[1..].each do |range|
        @state.uncompiled << Utf8Node.new(last: Utf8LastTransition.new(range.start, range.end))
      end
    end

    private def add_empty : Nil
      @state.uncompiled << Utf8Node.new
    end

    private def pop_freeze(next_id : StateID) : Array(Transition)
      node = @state.uncompiled.pop || raise "expected an uncompiled UTF-8 node"
      node.set_last_transition(next_id)
      node.trans
    end

    private def pop_root : Array(Transition)
      raise "expected a single UTF-8 root node" unless @state.uncompiled.size == 1
      raise "expected a fully frozen UTF-8 root" if @state.uncompiled.first.last
      (@state.uncompiled.pop || raise "expected a UTF-8 root node").trans
    end

    private def top_last_freeze(next_id : StateID) : Nil
      last_index = @state.uncompiled.size - 1
      raise "expected an uncompiled UTF-8 node" if last_index < 0
      @state.uncompiled[last_index].set_last_transition(next_id)
    end
  end

  private struct LiteralTrieTransition
    getter byte : UInt8
    getter next : Int32

    def initialize(@byte : UInt8, @next : Int32)
    end

    def inspect(io : IO) : Nil
      Regex::Automata::DebugByte.new(@byte).inspect(io)
      io << " => " << @next
    end
  end

  private class LiteralTrieState
    getter transitions : Array(LiteralTrieTransition)
    getter chunks : Array(Int32)

    def initialize
      @transitions = [] of LiteralTrieTransition
      @chunks = [] of Int32
    end

    def active_start : Int32
      @chunks.last? || 0
    end

    def add_match : Nil
      return if @transitions.empty? && !@chunks.empty?

      @chunks << @transitions.size.to_i32
    end

    def leaf? : Bool
      @transitions.empty?
    end

    def chunk_ranges : Array(Range(Int32, Int32))
      result = [] of Range(Int32, Int32)
      start = 0
      @chunks.each do |finish|
        result << (start...finish)
        start = finish
      end
      result << (start...@transitions.size)
      result
    end

    def inspect(io : IO) : Nil
      spacing = " "
      chunk_ranges.each_with_index do |chunk, chunk_index|
        io << spacing << "MATCH" if chunk_index > 0
        spacing = ""
        chunk.each_with_index do |transition_index, index|
          spacing = " "
          if index == 0 && chunk_index > 0
            io << ' '
          elsif index > 0
            io << ", "
          end
          @transitions[transition_index].inspect(io)
        end
      end
    end
  end

  private struct LiteralTrieFrame
    getter state_id : Int32
    @state : LiteralTrieState
    property chunk_index : Int32
    property transition_index : Int32
    getter union : Array(StateID)
    property sparse : Array(Transition)

    def initialize(@state_id : Int32, @state : LiteralTrieState)
      @chunk_index = 0
      @transition_index = 0
      @union = [] of StateID
      @sparse = [] of Transition
    end

    def current_chunk : Range(Int32, Int32)
      start = @chunk_index == 0 ? 0 : @state.chunks[@chunk_index - 1]
      finish = @chunk_index < @state.chunks.size ? @state.chunks[@chunk_index] : @state.transitions.size
      start...finish
    end

    def chunk_count : Int32
      @state.chunks.size.to_i32 + 1
    end
  end

  # A leftmost-first trie for alternations made entirely of literal bytes.
  # Match chunks preserve branch priority while shared prefixes avoid large
  # epsilon closures in the compiled Thompson NFA.
  class LiteralTrie
    @states : Array(LiteralTrieState)
    @reverse : Bool

    def initialize(@reverse : Bool)
      @states = [LiteralTrieState.new]
    end

    def self.forward : LiteralTrie
      new(false)
    end

    def self.reverse : LiteralTrie
      new(true)
    end

    def inspect(io : IO) : Nil
      io << "LiteralTrie(\n"
      @states.each_with_index do |state, index|
        io << index.to_s.rjust(6, '0') << ": "
        state.inspect(io)
        io << '\n'
      end
      io << ")\n"
    end

    def add(bytes : Bytes) : Nil
      current = 0
      indices = @reverse ? (bytes.size - 1).downto(0) : 0.upto(bytes.size - 1)
      indices.each do |index|
        byte = bytes[index]
        state = @states[current]
        start = state.active_start
        found = nil.as(Int32?)
        left = start
        right = state.transitions.size
        while left < right
          mid = (left + right) // 2
          if state.transitions[mid].byte < byte
            left = mid + 1
          else
            right = mid
          end
        end
        if left < state.transitions.size && state.transitions[left].byte == byte
          found = state.transitions[left].next
        else
          found = @states.size.to_i32
          @states << LiteralTrieState.new
          state.transitions.insert(left, LiteralTrieTransition.new(byte, found.not_nil!))
        end
        current = found.not_nil!
      end
      @states[current].add_match
    end

    def compile(builder : Builder) : ThompsonRef
      ending = builder.add_empty
      stack = [] of LiteralTrieFrame
      frame = LiteralTrieFrame.new(0, @states[0])
      loop do
        state = @states[frame.state_id]
        chunk = frame.current_chunk
        if frame.transition_index < chunk.end
          transition = state.transitions[frame.transition_index]
          frame.transition_index += 1
          if @states[transition.next].leaf?
            frame.sparse << Transition.new(transition.byte, transition.byte, ending)
          else
            frame.sparse << Transition.new(transition.byte, transition.byte, StateID.new(0))
            stack << frame
            frame = LiteralTrieFrame.new(transition.next, @states[transition.next])
          end
          next
        end

        unless frame.sparse.empty?
          chunk_id = if frame.sparse.size == 1
                       builder.add_state(ByteRange.new(frame.sparse.pop))
                     else
                       transitions = frame.sparse
                       frame.sparse = [] of Transition
                       builder.add_state(Sparse.new(transitions))
                     end
          frame.union << chunk_id
        end
        if frame.chunk_index + 1 < frame.chunk_count
          frame.union << ending
          frame.chunk_index += 1
          frame.transition_index = frame.current_chunk.begin
          next
        end

        start = builder.add_state(Union.new(frame.union))
        return ThompsonRef.new(start, ending) if stack.empty?

        frame = stack.pop
        placeholder = frame.sparse.size - 1
        old = frame.sparse[placeholder]
        frame.sparse[placeholder] = Transition.new(old.start, old.end, start)
      end
    end
  end

  # Thompson NFA builder
  class Builder
    @states : Array(State)
    @start_anchored : StateID
    @start_unanchored : StateID
    @start_pattern : Array(StateID)
    @utf8 : Bool
    @reverse : Bool
    @shrink : Bool
    @look_matcher : Regex::Automata::LookMatcher
    @size_limit : Int64?
    @memory_states : Int64
    @pattern_id : PatternID?
    @captures : Array(Array(String?))
    @manual_capture_ids : Set(StateID)
    @capture_end_ids : Set(StateID)
    @reverse_unions : Set(StateID)

    def initialize(utf8 : Bool = false, reverse : Bool = false, shrink : Bool = false, @size_limit : Int64? = nil)
      @states = [] of State
      @start_anchored = StateID.new(0)
      @start_unanchored = StateID.new(0)
      @start_pattern = [] of StateID
      @utf8 = utf8
      @reverse = reverse
      @shrink = shrink
      @look_matcher = Regex::Automata::LookMatcher.new
      @memory_states = 0_i64
      @pattern_id = nil
      @captures = [] of Array(String?)
      @manual_capture_ids = Set(StateID).new
      @capture_end_ids = Set(StateID).new
      @reverse_unions = Set(StateID).new
    end

    def clear : Nil
      @states.clear
      @start_pattern.clear
      @start_anchored = StateID::ZERO
      @start_unanchored = StateID::ZERO
      @pattern_id = nil
      @captures.clear
      @manual_capture_ids.clear
      @capture_end_ids.clear
      @reverse_unions.clear
      @memory_states = 0_i64
    end

    def start_pattern : PatternID
      raise "must call 'finish_pattern' first" if @pattern_id
      raise BuildError.too_many_patterns(@start_pattern.size.to_i64) if @start_pattern.size.to_i64 >= PatternID::LIMIT

      pid = PatternID.new(@start_pattern.size)
      @pattern_id = pid
      @start_pattern << StateID::ZERO
      pid
    end

    def finish_pattern(start_id : StateID) : PatternID
      pid = current_pattern_id
      @start_pattern[pid.to_i] = start_id
      @pattern_id = nil
      pid
    end

    def current_pattern_id : PatternID
      @pattern_id || raise "must call 'start_pattern' first"
    end

    def pattern_len : Int32
      @start_pattern.size.to_i32
    end

    def add_empty : StateID
      add_state(Empty.new(StateID::ZERO))
    end

    def add_union(alternates : Array(StateID)) : StateID
      add_state(Union.new(alternates.dup))
    end

    def add_union_reverse(alternates : Array(StateID)) : StateID
      id = add_union(alternates)
      @reverse_unions.add(id)
      id
    end

    def add_range(transition : Transition) : StateID
      add_state(ByteRange.new(transition))
    end

    def add_sparse(transitions : Array(Transition)) : StateID
      transitions.each_cons_pair do |left, right|
        raise ArgumentError.new("sparse transitions must be ordered and non-overlapping") if left.end >= right.start
      end
      add_state(Sparse.new(transitions.dup))
    end

    def add_look(next_id : StateID, kind : Look::Kind) : StateID
      add_state(Look.new(kind, next_id))
    end

    def add_capture_start(next_id : StateID, group_index : UInt32, name : String?) : StateID
      pid = current_pattern_id
      raise BuildError.invalid_capture_index(group_index) if group_index.to_i64 >= Regex::Automata::SmallIndex::LIMIT
      while @captures.size <= pid.to_i
        @captures << ([] of String?)
      end
      names = @captures[pid.to_i]
      while names.size < group_index.to_i
        names << nil
      end
      names << name if names.size == group_index.to_i
      id = add_state(Capture.new(next_id, pid, group_index.to_i32, 0))
      @manual_capture_ids.add(id)
      id
    end

    def add_capture_end(next_id : StateID, group_index : UInt32) : StateID
      pid = current_pattern_id
      raise BuildError.invalid_capture_index(group_index) if group_index.to_i64 >= Regex::Automata::SmallIndex::LIMIT
      id = add_state(Capture.new(next_id, pid, group_index.to_i32, 0))
      @manual_capture_ids.add(id)
      @capture_end_ids.add(id)
      id
    end

    def add_fail : StateID
      add_state(Fail.new)
    end

    def add_match : StateID
      add_state(Match.new(current_pattern_id))
    end

    def patch(from : StateID, to : StateID) : Nil
      state = @states[from.to_i]
      case state
      when Sparse
        raise "cannot patch from a sparse NFA state"
      when Union
        state.alternates << to
        @memory_states += sizeof(StateID).to_i64
        check_size_limit!
      when BinaryUnion
        @states[from.to_i] = Union.new([state.alt1, state.alt2, to])
        @memory_states += 3_i64 * sizeof(StateID).to_i64
        check_size_limit!
      when Fail, Match
        # Terminal states have no outgoing transition.
      else
        @states[from.to_i] = update_state_target(state, to)
      end
    end

    def set_utf8(yes : Bool) : Nil
      @utf8 = yes
    end

    def get_utf8 : Bool
      @utf8
    end

    def get_look_matcher : Regex::Automata::LookMatcher
      @look_matcher
    end

    # Add a new state and return its ID
    def add_state(state : State) : StateID
      if @states.size.to_i64 >= StateID::LIMIT
        raise BuildError.too_many_states(@states.size.to_i64)
      end
      id = StateID.new(@states.size)
      @states << state
      @memory_states += state_memory_usage(state)
      check_size_limit!
      id
    end

    def set_size_limit(limit : Int64?) : Nil
      @size_limit = limit
      check_size_limit!
    end

    def get_size_limit : Int64?
      @size_limit
    end

    def memory_usage : Int64
      @states.size.to_i64 * 32_i64 + @memory_states
    end

    private def check_size_limit! : Nil
      if limit = @size_limit
        raise BuildError.exceeded_size_limit(limit) if memory_usage > limit
      end
    end

    private def state_memory_usage(state : State) : Int64
      case state
      when Sparse
        state.transitions.size.to_i64 * sizeof(Transition).to_i64
      when Union
        state.alternates.size.to_i64 * sizeof(StateID).to_i64
      else
        0_i64
      end
    end

    def set_state(state_id : StateID, state : State) : Nil
      @memory_states += state_memory_usage(state) - state_memory_usage(@states[state_id.to_i])
      @states[state_id.to_i] = state
      check_size_limit!
    end

    def state(state_id : StateID) : State
      @states[state_id.to_i]
    end

    # Set the unanchored start state
    def set_start_unanchored(id : StateID)
      @start_unanchored = id
    end

    # Set the anchored start state
    def set_start_anchored(id : StateID)
      @start_anchored = id
    end

    # Set reverse mode
    def set_reverse(reverse : Bool)
      @reverse = reverse
    end

    # Get reverse mode
    def get_reverse : Bool
      @reverse
    end

    def set_look_matcher(look_matcher : Regex::Automata::LookMatcher)
      @look_matcher = look_matcher
    end

    def build(start_anchored : StateID, start_unanchored : StateID) : NFA
      set_start_anchored(start_anchored)
      set_start_unanchored(start_unanchored)
      build
    end

    # Add a pattern start state
    def add_pattern_start(id : StateID)
      @start_pattern << id
    end

    # Returns the universal set of valid Unicode scalar value ranges
    private def universal_unicode_ranges : Array(Range(UInt32, UInt32))
      # Valid Unicode scalar values: 0x0..0xD7FF and 0xE000..0x10FFFF
      [
        0x000000_u32..0x00D7FF_u32,
        0x00E000_u32..0x10FFFF_u32,
      ]
    end

    # Subtract ranges_to_subtract from ranges (both sorted, non-overlapping)
    # Returns sorted, non-overlapping complement ranges
    private def subtract_ranges(ranges : Array(Range(UInt32, UInt32)), ranges_to_subtract : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      result = [] of Range(UInt32, UInt32)
      i = 0
      ranges.each do |base|
        current_start = base.begin
        current_end = base.end
        # Skip subtract ranges that end before current start
        while i < ranges_to_subtract.size && ranges_to_subtract[i].end < current_start
          i += 1
        end
        # Process overlapping subtract ranges
        j = i
        while j < ranges_to_subtract.size && ranges_to_subtract[j].begin <= current_end
          sub = ranges_to_subtract[j]
          if sub.begin > current_start
            # Add portion before subtract range
            result << (current_start..sub.begin - 1)
          end
          # Move current_start past subtract range
          current_start = sub.end + 1
          break if current_start > current_end
          j += 1
        end
        # Add remaining portion after last subtract range
        if current_start <= current_end
          result << (current_start..current_end)
        end
      end
      result
    end

    # Returns the universal set of byte values
    private def universal_byte_ranges : Array(Range(UInt8, UInt8))
      [0x00_u8..0xFF_u8]
    end

    # Compute complement of byte ranges within 0x00..0xFF
    private def complement_byte_ranges(ranges : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      result = [] of Range(UInt8, UInt8)
      prev = 0_i32
      ranges.each do |range|
        if range.begin.to_i32 > prev
          result << (prev.to_u8..(range.begin.to_i32 - 1).to_u8)
        end
        prev = range.end.to_i32 + 1
        break if prev > 0xFF
      end
      if prev <= 0xFF
        result << (prev.to_u8..0xFF_u8)
      end
      result
    end

    # Build a literal pattern (sequence of bytes)
    def build_literal(bytes : Bytes, pattern_id : PatternID = PatternID.new(0)) : ThompsonRef
      # For empty literal, return a match state
      if bytes.empty?
        match_id = add_state(Match.new(pattern_id))
        return ThompsonRef.new(match_id, match_id)
      end

      # Build chain of byte range states
      start_id = nil
      prev_id = nil

      bytes.each do |byte|
        trans = Transition.new(byte, byte, StateID.new(0)) # placeholder
        state = ByteRange.new(trans)
        state_id = add_state(state)

        if prev_id
          # Update previous transition to point to this state
          update_transition_target(prev_id, state_id)
        else
          start_id = state_id
        end
        prev_id = state_id
      end

      # Last state should be a match
      match_id = add_state(Match.new(pattern_id))
      update_transition_target(prev_id, match_id) if prev_id

      ThompsonRef.new(start_id || match_id, match_id)
    end

    # Build alternation between two sub-NFAs
    def build_alternation(left : ThompsonRef, right : ThompsonRef, pattern_id : PatternID = PatternID.new(0)) : ThompsonRef
      # Create union state that epsilon-transitions to both alternatives
      union_start = add_state(BinaryUnion.new(left.start, right.start))
      # Create common match end state
      match_end = add_state(Match.new(pattern_id))
      # Patch both ends to point to common match state
      update_transition_target(left.end, match_end)
      update_transition_target(right.end, match_end)
      ThompsonRef.new(union_start, match_end)
    end

    # Build concatenation of two sub-NFAs
    def build_concatenation(first : ThompsonRef, second : ThompsonRef) : ThompsonRef
      # If first.end is a Match state, replace it with Empty to avoid intermediate matches
      replace_match_with_empty(first.end)
      # Patch the end of first sub-NFA to point to start of second
      update_transition_target(first.end, second.start)
      ThompsonRef.new(first.start, second.end)
    end

    # Build repetition (kleene star)
    def build_repetition(child : ThompsonRef, min : Int32, max : Int32?, greedy : Bool = true, pattern_id : PatternID = PatternID.new(0)) : ThompsonRef
      # Handle special cases
      if min == 0 && max.nil?
        # Kleene star: 0 or more repetitions
        # Create new end state (match state for empty string acceptance)
        new_end = add_state(Match.new(pattern_id))
        # Determine order based on greediness
        start_alternates = greedy ? [child.start, new_end] : [new_end, child.start]
        loop_alternates = greedy ? [child.start, new_end] : [new_end, child.start]
        # Create start union: epsilon to child.start OR to new_end (skip)
        start_union = add_state(BinaryUnion.new(start_alternates[0], start_alternates[1]))
        # Create loop union at child.end: epsilon to child.start (loop) OR to new_end
        loop_union = add_state(BinaryUnion.new(loop_alternates[0], loop_alternates[1]))
        update_transition_target(child.end, loop_union)
        ThompsonRef.new(start_union, new_end)
      elsif min == 1 && max.nil?
        # Plus: 1 or more repetitions
        # Create new end state (match state for acceptance after at least one)
        new_end = add_state(Match.new(pattern_id))
        # Determine order based on greediness
        loop_alternates = greedy ? [child.start, new_end] : [new_end, child.start]
        # Create loop union at child.end: epsilon to child.start (loop) OR to new_end
        loop_union = add_state(BinaryUnion.new(loop_alternates[0], loop_alternates[1]))
        update_transition_target(child.end, loop_union)
        ThompsonRef.new(child.start, new_end)
      elsif min == 0 && max == 1
        # Optional: 0 or 1
        # Determine order based on greediness
        alternates = greedy ? [child.start, child.end] : [child.end, child.start]
        # Create union start: epsilon to child.start OR to child.end (skip)
        start_union = add_state(BinaryUnion.new(alternates[0], alternates[1]))
        ThompsonRef.new(start_union, child.end)
      else
        # General case {min,max}
        build_general_repetition(child, min, max, greedy, pattern_id)
      end
    end

    private def build_general_repetition(child : ThompsonRef, min : Int32, max : Int32?, greedy : Bool, pattern_id : PatternID) : ThompsonRef
      # First build at least min copies
      result = if min > 0
                 # Build chain of min copies
                 build_min_copies(child, min, pattern_id)
               else
                 # Start with empty match
                 empty_match = add_state(Match.new(pattern_id))
                 ThompsonRef.new(empty_match, empty_match)
               end

      # Handle remaining repetitions
      if max.nil?
        # {min,} - unbounded upper limit, add Kleene star
        star_ref = build_repetition(child, 0, nil, greedy, pattern_id)
        # Concatenate min copies with star
        if min > 0
          build_concatenation(result, star_ref)
        else
          star_ref
        end
      else
        # {min,max} with finite max
        optional_count = max - min
        if optional_count > 0
          # Build optional copies
          optional_ref = build_optional_copies(child, optional_count, greedy, pattern_id)
          # Concatenate min copies with optional chain
          if min > 0
            build_concatenation(result, optional_ref)
          else
            optional_ref
          end
        else
          # min == max, just the min copies
          result
        end
      end
    end

    private def build_min_copies(child : ThompsonRef, count : Int32, pattern_id : PatternID) : ThompsonRef
      if count <= 0
        empty_match = add_state(Match.new(pattern_id))
        return ThompsonRef.new(empty_match, empty_match)
      end

      # Build chain of 'count' copies of child
      # Create fresh copy for each repetition to avoid modifying shared states
      result = copy_subgraph(child.start, child.end)
      (count - 1).times do
        next_copy = copy_subgraph(child.start, child.end)
        result = build_concatenation(result, next_copy)
      end
      result
    end

    private def build_optional_copies(child : ThompsonRef, count : Int32, greedy : Bool, pattern_id : PatternID) : ThompsonRef
      if count <= 0
        empty_match = add_state(Match.new(pattern_id))
        return ThompsonRef.new(empty_match, empty_match)
      end

      # Build chain of 'count' optional copies of child
      # Each optional copy needs its own child subgraph
      result = build_repetition(copy_subgraph(child.start, child.end), 0, 1, greedy, pattern_id)
      (count - 1).times do
        next_copy = copy_subgraph(child.start, child.end)
        next_optional = build_repetition(next_copy, 0, 1, greedy, pattern_id)
        result = build_concatenation(result, next_optional)
      end
      result
    end

    # Build character class
    def build_class(ranges : Array(Range(UInt8, UInt8)), negated : Bool = false, pattern_id : PatternID = PatternID.new(0)) : ThompsonRef
      if negated
        # Compute complement byte ranges (0x00..0xFF minus given ranges)
        complement = complement_byte_ranges(ranges)
        return build_class(complement, false, pattern_id)
      end

      # Convert ranges to transitions
      transitions = ranges.map do |range|
        Transition.new(range.begin, range.end, StateID.new(0))
      end

      if transitions.empty?
        fail_id = add_state(Fail.new)
        match_id = add_state(Match.new(pattern_id))
        return ThompsonRef.new(fail_id, match_id)
      end

      class_state = if transitions.size == 1
                      add_state(ByteRange.new(transitions.first))
                    else
                      add_state(Sparse.new(transitions))
                    end

      match_id = add_state(Match.new(pattern_id))
      update_transition_target(class_state, match_id)
      ThompsonRef.new(class_state, match_id)
    end

    # Build Unicode character class (codepoint ranges)
    def build_unicode_class(ranges : Array(Range(UInt32, UInt32)), negated : Bool = false, pattern_id : PatternID = PatternID.new(0)) : ThompsonRef
      if negated
        # Compute complement of property ranges within valid Unicode scalar values
        universal = universal_unicode_ranges()
        complement = subtract_ranges(universal, ranges)
        # Build NFA for complement ranges (positive)
        return build_unicode_class(complement, false, pattern_id)
      end

      if ranges.empty?
        fail_id = add_state(Fail.new)
        match_id = add_state(Match.new(pattern_id))
        ThompsonRef.new(fail_id, match_id)
      elsif @reverse
        if @shrink
          build_reverse_unicode_ranges_with_trie(ranges)
        else
          build_reverse_unicode_ranges_with_suffix(ranges)
        end
      else
        build_unicode_ranges_with_utf8_compiler(ranges)
      end
    end

    private def build_unicode_ranges_with_utf8_compiler(ranges : Array(Range(UInt32, UInt32))) : ThompsonRef
      compiler = Utf8Compiler.new(self)
      ranges.each do |range|
        utf8_seq = ::Regex::Automata::Utf8Sequences.new(range.begin.chr, range.end.chr)
        while seq = utf8_seq.next
          compiler.add(seq.ranges)
        end
      end
      compiler.finish
    end

    private def build_reverse_unicode_ranges_with_suffix(ranges : Array(Range(UInt32, UInt32))) : ThompsonRef
      cache = Utf8SuffixMap.new(1_000)
      cache.clear
      union_start = add_state(Union.new([] of StateID))
      target = add_state(Empty.new(StateID.new(0)))

      ranges.each do |range|
        utf8_seq = ::Regex::Automata::Utf8Sequences.new(range.begin.chr, range.end.chr)
        while seq = utf8_seq.next
          state_id = target
          seq.ranges.each do |seq_range|
            key = Utf8SuffixKey.new(state_id, seq_range.start, seq_range.end)
            hash = cache.hash(key)
            if cached = cache.get(key, hash)
              state_id = cached
              next
            end

            trans = Transition.new(seq_range.start, seq_range.end, state_id)
            state_id = add_state(ByteRange.new(trans))
            cache.set(key, hash, state_id)
          end

          update_transition_target(union_start, state_id)
        end
      end

      ThompsonRef.new(union_start, target)
    end

    private def build_reverse_unicode_ranges_with_trie(ranges : Array(Range(UInt32, UInt32))) : ThompsonRef
      trie = RangeTrie.new
      ranges.each do |range|
        utf8_seq = ::Regex::Automata::Utf8Sequences.new(range.begin.chr, range.end.chr)
        while seq = utf8_seq.next
          trie.insert(seq.ranges.reverse)
        end
      end

      compiler = Utf8Compiler.new(self)
      trie.each do |ranges|
        compiler.add(ranges)
      end
      compiler.finish
    end

    # Build a single UTF-8 sequence (concatenation of byte ranges)
    private def build_utf8_sequence(seq : ::Regex::Automata::Utf8Sequence, pattern_id : PatternID) : ThompsonRef
      byte_ranges = if @reverse
                      seq.ranges.reverse
                    else
                      seq.ranges
                    end

      # Build concatenation of byte ranges in sequence.
      refs = byte_ranges.map do |range|
        build_class([range.start..range.end], false, pattern_id)
      end

      if refs.empty?
        match_id = add_state(Match.new(pattern_id))
        ThompsonRef.new(match_id, match_id)
      elsif refs.size == 1
        refs.first
      else
        # Build concatenation chain
        result = refs.first
        refs[1..].each do |next_ref|
          result = build_concatenation(result, next_ref)
        end
        result
      end
    end

    # Build dot metacharacter
    def build_dot(kind : Regex::Syntax::Hir::Dot, pattern_id : PatternID = PatternID.new(0)) : ThompsonRef
      case kind
      when Regex::Syntax::Hir::Dot::AnyByte
        # Match any single byte (0-255)
        build_class([0_u8..255_u8], false, pattern_id)
      when Regex::Syntax::Hir::Dot::AnyByteExceptLF
        # Match any byte except line feed (10)
        ranges = [] of Range(UInt8, UInt8)
        ranges << (0_u8..9_u8) if 0_u8 <= 9_u8
        ranges << (11_u8..255_u8) if 11_u8 <= 255_u8
        build_class(ranges, false, pattern_id)
      when Regex::Syntax::Hir::Dot::AnyByteExceptCRLF
        # Match any byte except carriage return (13) and line feed (10)
        ranges = [] of Range(UInt8, UInt8)
        # 0-9, 11-12, 14-255
        ranges << (0_u8..9_u8) if 0_u8 <= 9_u8
        ranges << (11_u8..12_u8) if 11_u8 <= 12_u8
        ranges << (14_u8..255_u8) if 14_u8 <= 255_u8
        build_class(ranges, false, pattern_id)
      when Regex::Syntax::Hir::Dot::AnyChar
        build_utf8_any_char(pattern_id)
      when Regex::Syntax::Hir::Dot::AnyCharExceptLF
        build_utf8_any_char_except_lf(pattern_id)
      when Regex::Syntax::Hir::Dot::AnyCharExceptCRLF
        build_utf8_any_char_except_crlf(pattern_id)
      else
        raise "Unsupported dot kind: #{kind}"
      end
    end

    # Build UTF-8 any character (Unicode scalar value)
    private def build_utf8_any_char(pattern_id : PatternID) : ThompsonRef
      # Four alternatives: 1-byte, 2-byte, 3-byte, 4-byte sequences
      # 1-byte: 0x00-0x7F
      single = build_class([0x00_u8..0x7F_u8], false, pattern_id)
      # 2-byte: first 0xC0-0xDF, second 0x80-0xBF
      second_first = build_class([0xC0_u8..0xDF_u8], false, pattern_id)
      second_second = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      double = build_concatenation(second_first, second_second)
      # 3-byte: first 0xE0-0xEF, second 0x80-0xBF, third 0x80-0xBF
      third_first = build_class([0xE0_u8..0xEF_u8], false, pattern_id)
      third_second = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      third_third = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      triple = build_concatenation(third_first, third_second)
      triple = build_concatenation(triple, third_third)
      # 4-byte: first 0xF0-0xF7, second 0x80-0xBF, third 0x80-0xBF, fourth 0x80-0xBF
      fourth_first = build_class([0xF0_u8..0xF7_u8], false, pattern_id)
      fourth_second = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      fourth_third = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      fourth_fourth = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      quadruple = build_concatenation(fourth_first, fourth_second)
      quadruple = build_concatenation(quadruple, fourth_third)
      quadruple = build_concatenation(quadruple, fourth_fourth)
      # Union all four alternatives
      alt1 = build_alternation(single, double, pattern_id)
      alt2 = build_alternation(alt1, triple, pattern_id)
      build_alternation(alt2, quadruple, pattern_id)
    end

    # Build UTF-8 any character except line feed
    private def build_utf8_any_char_except_lf(pattern_id : PatternID) : ThompsonRef
      # Single-byte range excluding LF (0x0A)
      single_ranges = [] of Range(UInt8, UInt8)
      single_ranges << (0x00_u8..0x09_u8) if 0x00_u8 <= 0x09_u8
      single_ranges << (0x0B_u8..0x7F_u8) if 0x0B_u8 <= 0x7F_u8
      single = build_class(single_ranges, false, pattern_id)
      # 2-byte, 3-byte, 4-byte sequences unchanged (they don't contain LF)
      second_first = build_class([0xC0_u8..0xDF_u8], false, pattern_id)
      second_second = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      double = build_concatenation(second_first, second_second)
      third_first = build_class([0xE0_u8..0xEF_u8], false, pattern_id)
      third_second = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      third_third = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      triple = build_concatenation(third_first, third_second)
      triple = build_concatenation(triple, third_third)
      fourth_first = build_class([0xF0_u8..0xF7_u8], false, pattern_id)
      fourth_second = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      fourth_third = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      fourth_fourth = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      quadruple = build_concatenation(fourth_first, fourth_second)
      quadruple = build_concatenation(quadruple, fourth_third)
      quadruple = build_concatenation(quadruple, fourth_fourth)
      # Union all four alternatives
      alt1 = build_alternation(single, double, pattern_id)
      alt2 = build_alternation(alt1, triple, pattern_id)
      build_alternation(alt2, quadruple, pattern_id)
    end

    # Build UTF-8 any character except carriage return and line feed
    private def build_utf8_any_char_except_crlf(pattern_id : PatternID) : ThompsonRef
      # Single-byte range excluding LF (0x0A) and CR (0x0D)
      single_ranges = [] of Range(UInt8, UInt8)
      single_ranges << (0x00_u8..0x09_u8) if 0x00_u8 <= 0x09_u8
      single_ranges << (0x0B_u8..0x0C_u8) if 0x0B_u8 <= 0x0C_u8
      single_ranges << (0x0E_u8..0x7F_u8) if 0x0E_u8 <= 0x7F_u8
      single = build_class(single_ranges, false, pattern_id)
      # 2-byte, 3-byte, 4-byte sequences unchanged (they don't contain LF or CR)
      second_first = build_class([0xC0_u8..0xDF_u8], false, pattern_id)
      second_second = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      double = build_concatenation(second_first, second_second)
      third_first = build_class([0xE0_u8..0xEF_u8], false, pattern_id)
      third_second = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      third_third = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      triple = build_concatenation(third_first, third_second)
      triple = build_concatenation(triple, third_third)
      fourth_first = build_class([0xF0_u8..0xF7_u8], false, pattern_id)
      fourth_second = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      fourth_third = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      fourth_fourth = build_class([0x80_u8..0xBF_u8], false, pattern_id)
      quadruple = build_concatenation(fourth_first, fourth_second)
      quadruple = build_concatenation(quadruple, fourth_third)
      quadruple = build_concatenation(quadruple, fourth_fourth)
      # Union all four alternatives
      alt1 = build_alternation(single, double, pattern_id)
      alt2 = build_alternation(alt1, triple, pattern_id)
      build_alternation(alt2, quadruple, pattern_id)
    end

    # Build the final NFA
    def build(group_info : Regex::Automata::GroupInfo = Regex::Automata::GroupInfo.empty) : NFA
      raise "must call 'finish_pattern' first" if @pattern_id
      if !@captures.empty?
        group_info = Regex::Automata::GroupInfo.new(@captures.map(&.dup))
      end
      remap = Array.new(@states.size) { StateID.new(0) }
      final_states = [] of State

      @states.each_with_index do |state, index|
        sid = StateID.new(index)
        case state
        when Empty
          next
        when Match
          if state.next
            next
          else
            remap[index] = StateID.new(final_states.size)
            final_states << state
          end
        when Sparse
          replacement = case state.transitions.size
                        when 0
                          Fail.new.as(State)
                        when 1
                          ByteRange.new(state.transitions.first).as(State)
                        else
                          state.as(State)
                        end
          remap[index] = StateID.new(final_states.size)
          final_states << replacement
        when Union
          alternates = @reverse_unions.includes?(sid) ? state.alternates.reverse : state.alternates
          replacement = case alternates.size
                        when 0
                          Fail.new.as(State)
                        when 1
                          next
                        when 2
                          BinaryUnion.new(alternates[0], alternates[1]).as(State)
                        else
                          Union.new(alternates).as(State)
                        end
          remap[index] = StateID.new(final_states.size)
          final_states << replacement
        when Capture
          replacement = if @manual_capture_ids.includes?(sid)
                          slot = group_info.slot(state.pattern_id, state.group_index) ||
                                 raise "invalid capture index"
                          slot += 1 if @capture_end_ids.includes?(sid)
                          Capture.new(state.next, state.pattern_id, state.group_index, slot).as(State)
                        else
                          state.as(State)
                        end
          remap[index] = StateID.new(final_states.size)
          final_states << replacement
        else
          remap[index] = StateID.new(final_states.size)
          final_states << state
        end
      end

      remapped = Array.new(@states.size, false)
      @states.each_with_index do |state, index|
        sid = StateID.new(index)
        next if remapped[index]
        next unless goto = goto_target(state)

        terminal = goto
        while next_goto = goto_target(@states[terminal.to_i])
          terminal = next_goto
        end
        final_id = remap[terminal.to_i]
        remap[index] = final_id
        remapped[index] = true

        cursor = goto
        while next_goto = goto_target(@states[cursor.to_i])
          remap[cursor.to_i] = final_id
          remapped[cursor.to_i] = true
          cursor = next_goto
        end
      end

      final_states.map_with_index! do |state, _index|
        remap_state(state, remap)
      end

      remapped_start_pattern = @start_pattern.map { |sid| remap[sid.to_i] }
      NFA.new(
        final_states,
        remap[@start_anchored.to_i],
        remap[@start_unanchored.to_i],
        remapped_start_pattern,
        @utf8,
        @reverse,
        group_info,
        @look_matcher
      )
    rescue ex : Regex::Automata::GroupInfoError
      raise BuildError.captures(ex)
    end

    # Update the target of a state's transition
    # Used internally to patch placeholder transitions
    def update_transition_target(state_id : StateID, target_id : StateID)
      state = @states[state_id.to_i]
      new_state = update_state_target(state, target_id)
      @states[state_id.to_i] = new_state
    end

    # Replace a Match state with an Empty state (for concatenation)
    # Returns the new Empty state's ID (same as input)
    def replace_match_with_empty(state_id : StateID) : StateID
      state = @states[state_id.to_i]
      case state
      when Match
        # Create Empty state with same next target (if any)
        next_id = state.next || StateID.new(0)
        @states[state_id.to_i] = Empty.new(next_id)
      else
        # Not a Match, leave unchanged
      end
      state_id
    end

    private def update_state_target(state : State, target_id : StateID) : State
      case state
      when ByteRange
        trans = state.trans
        ByteRange.new(Transition.new(trans.start, trans.end, target_id))
      when Sparse
        new_transitions = state.transitions.map do |trans|
          Transition.new(trans.start, trans.end, target_id)
        end
        Sparse.new(new_transitions)
      when Look
        Look.new(state.kind, target_id)
      when Capture
        Capture.new(target_id, state.pattern_id, state.group_index, state.slot)
      when Empty
        Empty.new(target_id)
      when Match
        Match.new(state.pattern_id, target_id)
      when Union
        # Add target to alternates (creates new union with additional epsilon transition)
        Union.new(state.alternates + [target_id])
      when BinaryUnion
        # Convert to Union with 3 alternates
        Union.new([state.alt1, state.alt2, target_id])
      when Fail
        # Fail states have no outgoing transitions
        state
      else
        # Should never happen (exhaustive case)
        state
      end
    end

    private def goto_target(state : State) : StateID?
      case state
      when Empty
        state.next
      when Match
        state.next
      when Union
        state.alternates.size == 1 ? state.alternates.first : nil
      else
        nil
      end
    end

    private def remap_state(state : State, remap : Array(StateID)) : State
      case state
      when ByteRange
        trans = state.trans
        ByteRange.new(Transition.new(trans.start, trans.end, remap[trans.next.to_i]))
      when Sparse
        Sparse.new(
          state.transitions.map do |trans|
            Transition.new(trans.start, trans.end, remap[trans.next.to_i])
          end
        )
      when Dense
        Dense.new(state.transitions.map { |sid| remap[sid.to_i] })
      when Look
        Look.new(state.kind, remap[state.next.to_i])
      when Union
        Union.new(state.alternates.map { |sid| remap[sid.to_i] })
      when BinaryUnion
        BinaryUnion.new(remap[state.alt1.to_i], remap[state.alt2.to_i])
      when Capture
        Capture.new(remap[state.next.to_i], state.pattern_id, state.group_index, state.slot)
      when Match
        Match.new(state.pattern_id, state.next.try { |sid| remap[sid.to_i] })
      else
        state
      end
    end

    # Get all target state IDs from a state (for graph traversal)
    private def get_targets(state : State) : Array(StateID)
      case state
      when ByteRange
        [state.trans.next]
      when Sparse
        state.transitions.map(&.next)
      when Look, Capture, Empty
        [state.next]
      when Match
        state.next.try { |n| [n] } || [] of StateID
      when Union
        state.alternates
      when BinaryUnion
        [state.alt1, state.alt2]
      when Fail
        [] of StateID
      else
        [] of StateID
      end
    end

    # Create a deep copy of a Thompson subgraph
    private def copy_subgraph(start_id : StateID, end_id : StateID) : ThompsonRef
      # Map from original state ID to new state ID
      id_map = {} of StateID => StateID
      # Stack for DFS traversal
      stack = [start_id]

      # First pass: duplicate all reachable states
      while !stack.empty?
        orig_id = stack.pop
        next if id_map.has_key?(orig_id)

        # Duplicate state
        orig_state = @states[orig_id.to_i]
        new_id = add_state(orig_state)
        id_map[orig_id] = new_id

        # Push targets for traversal
        get_targets(orig_state).each do |target_id|
          # Only traverse targets that are within the same subgraph?
          # We'll traverse all reachable states; but we must avoid infinite loops.
          # Use visited check via id_map.
          unless id_map.has_key?(target_id)
            stack.push(target_id)
          end
        end
      end

      # Second pass: update transitions in copied states to point to copied targets
      id_map.each do |_orig_id, copied_id|
        state = @states[copied_id.to_i]
        new_targets = get_targets(state).map do |target_id|
          id_map[target_id]? || target_id
        end

        # Update state with new targets
        case state
        when ByteRange
          trans = state.trans
          @states[copied_id.to_i] = ByteRange.new(Transition.new(trans.start, trans.end, new_targets.first))
        when Sparse
          new_transitions = state.transitions.map_with_index do |t, i|
            Transition.new(t.start, t.end, new_targets[i])
          end
          @states[copied_id.to_i] = Sparse.new(new_transitions)
        when Look
          @states[copied_id.to_i] = Look.new(state.kind, new_targets.first)
        when Capture
          @states[copied_id.to_i] = Capture.new(new_targets.first, state.pattern_id, state.group_index, state.slot)
        when Empty
          @states[copied_id.to_i] = Empty.new(new_targets.first)
        when Match
          # Match state's next is optional
          next_target = new_targets.first? || nil
          @states[copied_id.to_i] = Match.new(state.pattern_id, next_target)
        when Union
          @states[copied_id.to_i] = Union.new(new_targets)
        when BinaryUnion
          @states[copied_id.to_i] = BinaryUnion.new(new_targets[0], new_targets[1])
        when Fail
          # No changes
        end
      end

      # Return reference to copied subgraph
      ThompsonRef.new(id_map[start_id], id_map[end_id])
    end
  end

  # Thompson NFA
  class NFA
    @has_capture : Bool
    @has_empty : Bool
    @look_set_any : Regex::Automata::LookSet
    @look_set_prefix_any : Regex::Automata::LookSet
    @byte_class_set : Regex::Automata::ByteClassSet
    @byte_classes : Regex::Automata::ByteClasses
    @look_matcher : Regex::Automata::LookMatcher

    getter states : Array(State)
    getter start_anchored : StateID
    getter start_unanchored : StateID
    getter start_pattern : Array(StateID)
    getter group_info : Regex::Automata::GroupInfo
    getter look_matcher : Regex::Automata::LookMatcher
    getter? utf8 : Bool
    getter? reverse : Bool

    def initialize(@states : Array(State), @start_anchored : StateID,
                   @start_unanchored : StateID, @start_pattern : Array(StateID),
                   @utf8 : Bool, @reverse : Bool = false,
                   @group_info : Regex::Automata::GroupInfo = Regex::Automata::GroupInfo.empty,
                   @look_matcher : Regex::Automata::LookMatcher = Regex::Automata::LookMatcher.new)
      @has_capture = false
      @has_empty = false
      @look_set_any = Regex::Automata::LookSet.empty
      @look_set_prefix_any = Regex::Automata::LookSet.empty
      @byte_class_set = compute_byte_class_set
      @byte_classes = @byte_class_set.byte_classes
      compute_prefix_metadata
    end

    def inspect(io : IO) : Nil
      io << "thompson::NFA(\n"
      @states.each_with_index do |state, index|
        mark = if index == @start_anchored.to_i
                 '^'
               elsif index == @start_unanchored.to_i
                 '>'
               else
                 ' '
               end
        io << mark << index.to_s.rjust(6, '0') << ": "
        state.inspect(io)
        io << '\n'
      end
      if @start_pattern.size > 1
        io << '\n'
        @start_pattern.each_with_index do |sid, pid|
          io << "START(" << pid.to_s.rjust(6, '0') << "): " << sid.to_i << '\n'
        end
      end
      io << "\ntransition equivalence classes: "
      @byte_classes.inspect(io)
      io << "\n)\n"
    end

    def self.config : ::Regex::Automata::HirCompilerConfig
      ::Regex::Automata::HirCompilerConfig.new
    end

    def self.compiler : ::Regex::Automata::HirCompiler
      ::Regex::Automata::HirCompiler.new
    end

    def self.new(pattern : String) : NFA
      compiler.build(pattern)
    end

    def self.new_many(patterns : Enumerable(String)) : NFA
      compiler.build_many(patterns.to_a)
    end

    def self.always_match : NFA
      builder = Builder.new
      start_id = builder.add_state(Capture.new(StateID.new(0), PatternID.new(0), 0, 0))
      end_id = builder.add_state(Capture.new(StateID.new(0), PatternID.new(0), 0, 1))
      match_id = builder.add_state(Match.new(PatternID.new(0)))
      builder.update_transition_target(start_id, end_id)
      builder.update_transition_target(end_id, match_id)
      builder.add_pattern_start(start_id)
      builder.set_start_anchored(start_id)
      builder.set_start_unanchored(start_id)
      builder.build(GroupInfo.new([[nil] of String?]))
    end

    def self.never_match : NFA
      fail_id = StateID.new(0)
      new([Fail.new] of State, fail_id, fail_id, [] of StateID, false, false, GroupInfo.empty)
    end

    # Get number of states
    def size : Int32
      @states.size
    end

    def pattern_len : Int32
      @start_pattern.size.to_i32
    end

    def patterns : PatternIter
      PatternIter.new(pattern_len)
    end

    def start_pattern(pid : PatternID) : StateID?
      @start_pattern[pid.to_i]?
    end

    def state(id : StateID) : State
      @states[id.to_i]
    end

    def has_capture : Bool
      @has_capture
    end

    def has_empty : Bool
      @has_empty
    end

    def is_utf8 : Bool
      @utf8
    end

    def is_reverse : Bool
      @reverse
    end

    def is_always_start_anchored : Bool
      @start_anchored == @start_unanchored
    end

    def look_set_any : Regex::Automata::LookSet
      @look_set_any
    end

    def look_set_prefix_any : Regex::Automata::LookSet
      @look_set_prefix_any
    end

    def byte_classes : Regex::Automata::ByteClasses
      @byte_classes
    end

    def byte_class_set : Regex::Automata::ByteClassSet
      @byte_class_set.dup
    end

    def memory_usage : Int32
      @states.size.to_i32 * 32 +
        @start_pattern.size.to_i32 * sizeof(StateID).to_i32 +
        @group_info.memory_usage +
        @states.sum { |state| state_memory_usage(state) }
    end

    # Compute epsilon closure of a set of NFA states
    def epsilon_closure(states : Set(StateID)) : Set(StateID)
      stack = states.to_a
      closure = Set(StateID).new(states)

      while !stack.empty?
        state_id = stack.pop
        state = @states[state_id.to_i]

        case state
        when Empty
          next_id = state.next
          unless closure.includes?(next_id)
            closure.add(next_id)
            stack.push(next_id)
          end
        when Union
          state.alternates.each do |alt_id|
            unless closure.includes?(alt_id)
              closure.add(alt_id)
              stack.push(alt_id)
            end
          end
        when BinaryUnion
          unless closure.includes?(state.alt1)
            closure.add(state.alt1)
            stack.push(state.alt1)
          end
          unless closure.includes?(state.alt2)
            closure.add(state.alt2)
            stack.push(state.alt2)
          end
        when Look, Capture
          # These have a single next pointer (epsilon transition)
          next_id = state.next
          unless closure.includes?(next_id)
            closure.add(next_id)
            stack.push(next_id)
          end
        when Match
          # Vendor determinization treats match states as terminal in epsilon
          # closure. Delayed match metadata is handled by the DFA builder.
        when Fail, ByteRange, Sparse, Dense
          # No epsilon transitions
        end
      end

      closure
    end

    # Compute epsilon closure of a set of NFA states, considering look-around assertions
    # look_have: set of look-around assertions satisfied at the current position
    def epsilon_closure_with_look(states : Set(StateID), look_have : Regex::Automata::LookSet) : Set(StateID)
      stack = states.to_a
      closure = Set(StateID).new(states)

      while !stack.empty?
        state_id = stack.pop
        state = @states[state_id.to_i]

        case state
        when Empty
          next_id = state.next
          unless closure.includes?(next_id)
            closure.add(next_id)
            stack.push(next_id)
          end
        when Union
          state.alternates.each do |alt_id|
            unless closure.includes?(alt_id)
              closure.add(alt_id)
              stack.push(alt_id)
            end
          end
        when BinaryUnion
          unless closure.includes?(state.alt1)
            closure.add(state.alt1)
            stack.push(state.alt1)
          end
          unless closure.includes?(state.alt2)
            closure.add(state.alt2)
            stack.push(state.alt2)
          end
        when Look
          # Look states are conditional epsilon transitions
          # Check if this look kind is satisfied
          look_kind_satisfied = case state.kind
                                when Look::Kind::StartLF
                                  look_have.includes?(Regex::Automata::Look::StartLF)
                                when Look::Kind::EndLF
                                  look_have.includes?(Regex::Automata::Look::EndLF)
                                when Look::Kind::StartCRLF
                                  look_have.includes?(Regex::Automata::Look::StartCRLF)
                                when Look::Kind::EndCRLF
                                  look_have.includes?(Regex::Automata::Look::EndCRLF)
                                when Look::Kind::WordBoundaryAscii
                                  look_have.includes?(Regex::Automata::Look::WordAscii) ||
                                    look_have.includes?(Regex::Automata::Look::WordStartAscii) ||
                                    look_have.includes?(Regex::Automata::Look::WordEndAscii)
                                when Look::Kind::NonWordBoundaryAscii
                                  look_have.includes?(Regex::Automata::Look::WordAsciiNegate)
                                when Look::Kind::WordBoundaryUnicode
                                  look_have.includes?(Regex::Automata::Look::WordUnicode) ||
                                    look_have.includes?(Regex::Automata::Look::WordStartUnicode) ||
                                    look_have.includes?(Regex::Automata::Look::WordEndUnicode)
                                when Look::Kind::NonWordBoundaryUnicode
                                  look_have.includes?(Regex::Automata::Look::WordUnicodeNegate)
                                when Look::Kind::WordStartAscii
                                  look_have.includes?(Regex::Automata::Look::WordStartAscii)
                                when Look::Kind::WordEndAscii
                                  look_have.includes?(Regex::Automata::Look::WordEndAscii)
                                when Look::Kind::WordStartUnicode
                                  look_have.includes?(Regex::Automata::Look::WordStartUnicode)
                                when Look::Kind::WordEndUnicode
                                  look_have.includes?(Regex::Automata::Look::WordEndUnicode)
                                when Look::Kind::WordStartHalfAscii
                                  look_have.includes?(Regex::Automata::Look::WordStartHalfAscii)
                                when Look::Kind::WordEndHalfAscii
                                  look_have.includes?(Regex::Automata::Look::WordEndHalfAscii)
                                when Look::Kind::WordStartHalfUnicode
                                  look_have.includes?(Regex::Automata::Look::WordStartHalfUnicode)
                                when Look::Kind::WordEndHalfUnicode
                                  look_have.includes?(Regex::Automata::Look::WordEndHalfUnicode)
                                when Look::Kind::StartText
                                  look_have.includes?(Regex::Automata::Look::Start)
                                when Look::Kind::EndText, Look::Kind::EndTextWithNewline
                                  look_have.includes?(Regex::Automata::Look::End)
                                else
                                  false
                                end

          if look_kind_satisfied
            next_id = state.next
            unless closure.includes?(next_id)
              closure.add(next_id)
              stack.push(next_id)
            end
          end
        when Capture
          # Capture states are unconditional epsilon transitions
          next_id = state.next
          unless closure.includes?(next_id)
            closure.add(next_id)
            stack.push(next_id)
          end
        when Match
          # Vendor determinization treats match states as terminal in epsilon
          # closure. Delayed match metadata is handled by the DFA builder.
        when Fail, ByteRange, Sparse, Dense
          # No epsilon transitions
        end
      end

      closure
    end

    def epsilon_closure_with_look_ordered(states : Enumerable(StateID), look_have : Regex::Automata::LookSet) : Array(StateID)
      ordered = [] of StateID
      seen = Set(StateID).new
      stack = [] of StateID

      states.to_a.reverse_each do |state_id|
        stack << state_id
      end

      until stack.empty?
        state_id = stack.pop
        next unless seen.add?(state_id)

        ordered << state_id
        state = @states[state_id.to_i]

        case state
        when Empty
          stack << state.next
        when Union
          state.alternates.reverse_each do |alt_id|
            stack << alt_id
          end
        when BinaryUnion
          stack << state.alt2
          stack << state.alt1
        when Look
          look_kind_satisfied = case state.kind
                                when Look::Kind::StartLF
                                  look_have.includes?(Regex::Automata::Look::StartLF)
                                when Look::Kind::EndLF
                                  look_have.includes?(Regex::Automata::Look::EndLF)
                                when Look::Kind::StartCRLF
                                  look_have.includes?(Regex::Automata::Look::StartCRLF)
                                when Look::Kind::EndCRLF
                                  look_have.includes?(Regex::Automata::Look::EndCRLF)
                                when Look::Kind::WordBoundaryAscii
                                  look_have.includes?(Regex::Automata::Look::WordAscii) ||
                                    look_have.includes?(Regex::Automata::Look::WordStartAscii) ||
                                    look_have.includes?(Regex::Automata::Look::WordEndAscii)
                                when Look::Kind::NonWordBoundaryAscii
                                  look_have.includes?(Regex::Automata::Look::WordAsciiNegate)
                                when Look::Kind::WordBoundaryUnicode
                                  look_have.includes?(Regex::Automata::Look::WordUnicode) ||
                                    look_have.includes?(Regex::Automata::Look::WordStartUnicode) ||
                                    look_have.includes?(Regex::Automata::Look::WordEndUnicode)
                                when Look::Kind::NonWordBoundaryUnicode
                                  look_have.includes?(Regex::Automata::Look::WordUnicodeNegate)
                                when Look::Kind::WordStartAscii
                                  look_have.includes?(Regex::Automata::Look::WordStartAscii)
                                when Look::Kind::WordEndAscii
                                  look_have.includes?(Regex::Automata::Look::WordEndAscii)
                                when Look::Kind::WordStartUnicode
                                  look_have.includes?(Regex::Automata::Look::WordStartUnicode)
                                when Look::Kind::WordEndUnicode
                                  look_have.includes?(Regex::Automata::Look::WordEndUnicode)
                                when Look::Kind::WordStartHalfAscii
                                  look_have.includes?(Regex::Automata::Look::WordStartHalfAscii)
                                when Look::Kind::WordEndHalfAscii
                                  look_have.includes?(Regex::Automata::Look::WordEndHalfAscii)
                                when Look::Kind::WordStartHalfUnicode
                                  look_have.includes?(Regex::Automata::Look::WordStartHalfUnicode)
                                when Look::Kind::WordEndHalfUnicode
                                  look_have.includes?(Regex::Automata::Look::WordEndHalfUnicode)
                                when Look::Kind::StartText
                                  look_have.includes?(Regex::Automata::Look::Start)
                                when Look::Kind::EndText, Look::Kind::EndTextWithNewline
                                  look_have.includes?(Regex::Automata::Look::End)
                                else
                                  false
                                end
          stack << state.next if look_kind_satisfied
        when Capture
          stack << state.next
        when Match, Fail, ByteRange, Sparse, Dense
        end
      end

      ordered
    end

    # Get transitions from a state for a given byte
    def transitions(state_id : StateID, byte : UInt8) : Set(StateID)
      state = @states[state_id.to_i]
      result = Set(StateID).new

      case state
      when ByteRange
        result.add(state.trans.next) if state.trans.matches?(byte)
      when Sparse
        state.transitions.each do |trans|
          result.add(trans.next) if trans.matches?(byte)
        end
      when Dense
        if next_id = state.matches_byte(byte)
          result.add(next_id)
        end
      end

      result
    end

    private def state_memory_usage(state : State) : Int32
      case state
      when ByteRange, Look, BinaryUnion, Capture, Match, Fail, Empty
        0
      when Sparse
        (state.transitions.size * sizeof(Transition)).to_i32
      when Dense
        (256 * sizeof(StateID)).to_i32
      when Union
        (state.alternates.size * sizeof(StateID)).to_i32
      else
        0
      end
    end

    private def compute_byte_class_set : Regex::Automata::ByteClassSet
      set = Regex::Automata::ByteClassSet.empty
      @states.each do |state|
        case state
        when ByteRange
          set.set_range(state.trans.start, state.trans.end)
        when Sparse
          state.transitions.each do |trans|
            set.set_range(trans.start, trans.end)
          end
        when Dense
          state.iter.each { |trans| set.set_range(trans.start, trans.end) }
        when Look
          looks = look_from_kind(state.kind)
          @look_set_any = @look_set_any.union(looks)
          looks.iter.each do |look|
            @look_matcher.add_to_byteset(look, set)
          end
        when Capture
          @has_capture = true
        end
      end
      set
    end

    private def compute_prefix_metadata : Nil
      stack = [] of StateID
      seen = Regex::Automata::SparseSet.new(@states.size)
      @start_pattern.each do |start_id|
        stack << start_id
        seen.clear
        prefix_any = Regex::Automata::LookSet.empty
        until stack.empty?
          state_id = stack.pop
          next unless seen.insert(state_id)

          case state = @states[state_id.to_i]
          when ByteRange, Sparse, Dense, Fail
          when Match
            @has_empty = true
          when Look
            prefix_any = prefix_any.union(look_from_kind(state.kind))
            stack << state.next
          when Union
            state.alternates.each { |next_id| stack << next_id }
          when BinaryUnion
            stack << state.alt2
            stack << state.alt1
          when Capture, Empty
            stack << state.next
          end
        end
        @look_set_prefix_any = @look_set_prefix_any.union(prefix_any)
      end
    end

    private def look_from_kind(kind : Look::Kind) : Regex::Automata::LookSet
      case kind
      when Look::Kind::StartLF
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::StartLF)
      when Look::Kind::EndLF
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::EndLF)
      when Look::Kind::StartCRLF
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::StartCRLF)
      when Look::Kind::EndCRLF
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::EndCRLF)
      when Look::Kind::WordBoundaryAscii
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordAscii)
      when Look::Kind::NonWordBoundaryAscii
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordAsciiNegate)
      when Look::Kind::WordBoundaryUnicode
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordUnicode)
      when Look::Kind::NonWordBoundaryUnicode
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordUnicodeNegate)
      when Look::Kind::WordStartAscii
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordStartAscii)
      when Look::Kind::WordEndAscii
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordEndAscii)
      when Look::Kind::WordStartUnicode
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordStartUnicode)
      when Look::Kind::WordEndUnicode
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordEndUnicode)
      when Look::Kind::WordStartHalfAscii
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordStartHalfAscii)
      when Look::Kind::WordEndHalfAscii
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordEndHalfAscii)
      when Look::Kind::WordStartHalfUnicode
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordStartHalfUnicode)
      when Look::Kind::WordEndHalfUnicode
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordEndHalfUnicode)
      when Look::Kind::StartText
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::Start)
      when Look::Kind::EndText
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::End)
      when Look::Kind::EndTextWithNewline
        Regex::Automata::LookSet.singleton(Regex::Automata::Look::End)
      else
        Regex::Automata::LookSet.empty
      end
    end
  end
end
