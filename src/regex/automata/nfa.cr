require "./utf8_sequences"
require "./look"
require "./captures"
require "./types"
require "./byte_classes"

module Regex::Automata::NFA
  alias StateID = Regex::Automata::StateID
  alias PatternID = Regex::Automata::PatternID

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
  alias State = ByteRange | Sparse | Look | Union | BinaryUnion | Capture | Match | Fail | Empty

  # Single byte range transition
  struct ByteRange
    getter trans : Transition

    def initialize(@trans : Transition)
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

    def matches_byte(byte : UInt8) : StateID?
      @transitions.find(&.matches?(byte)).try(&.next)
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
      StartText              # \A
      EndText                # \z
      EndTextWithNewline     # \Z
    end

    getter kind : Kind
    getter next : StateID

    def initialize(@kind : Kind, @next : StateID)
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

    def is_epsilon : Bool
      false
    end
  end

  # Fail state (no transitions)
  struct Fail
    def initialize
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

  # Thompson NFA builder
  class Builder
    @states : Array(State)
    @start_anchored : StateID
    @start_unanchored : StateID
    @start_pattern : Array(StateID)
    @utf8 : Bool
    @reverse : Bool
    @look_matcher : Regex::Automata::LookMatcher

    def initialize(utf8 : Bool = true, reverse : Bool = false)
      @states = [] of State
      @start_anchored = StateID.new(0)
      @start_unanchored = StateID.new(0)
      @start_pattern = [] of StateID
      @utf8 = utf8
      @reverse = reverse
      @look_matcher = Regex::Automata::LookMatcher.new
    end

    # Add a new state and return its ID
    def add_state(state : State) : StateID
      id = StateID.new(@states.size)
      @states << state
      id
    end

    def set_state(state_id : StateID, state : State) : Nil
      @states[state_id.to_i] = state
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

      # Convert each Unicode range to UTF-8 sequences
      sequences = [] of ::Regex::Automata::Utf8Sequence
      ranges.each do |range|
        start_char = range.begin.chr
        end_char = range.end.chr
        utf8_seq = ::Regex::Automata::Utf8Sequences.new(start_char, end_char)
        while seq = utf8_seq.next
          sequences << seq
        end
      end

      if @reverse
        return build_reverse_unicode_sequences(sequences, pattern_id)
      end

      # Build alternation of all sequences
      if sequences.empty?
        fail_id = add_state(Fail.new)
        match_id = add_state(Match.new(pattern_id))
        ThompsonRef.new(fail_id, match_id)
      elsif sequences.size == 1
        # Single sequence - build concatenation
        build_utf8_sequence(sequences.first, pattern_id)
      else
        # Multiple sequences - build alternation
        refs = sequences.map { |seq| build_utf8_sequence(seq, pattern_id) }
        # Build binary alternation tree
        result = refs.first
        refs[1..].each do |next_ref|
          result = build_alternation(result, next_ref, pattern_id)
        end
        result
      end
    end

    private def build_reverse_unicode_sequences(sequences : Array(::Regex::Automata::Utf8Sequence), pattern_id : PatternID) : ThompsonRef
      if sequences.empty?
        match_id = add_state(Match.new(pattern_id))
        return ThompsonRef.new(match_id, match_id)
      end

      cache = {} of Tuple(Int32, UInt8, UInt8) => StateID
      union_start = add_state(Union.new([] of StateID))
      match_end = add_state(Match.new(pattern_id))

      sequences.each do |seq|
        state_id = match_end
        seq.ranges.reverse_each do |range|
          key = {state_id.to_i, range.start, range.end}
          if cached = cache[key]?
            state_id = cached
            next
          end

          trans = Transition.new(range.start, range.end, state_id)
          state_id = add_state(ByteRange.new(trans))
          cache[key] = state_id
        end
        update_transition_target(union_start, state_id)
      end

      ThompsonRef.new(union_start, match_end)
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
      if @states.empty?
        fail_id = StateID.new(0)
        return NFA.new(
          [Fail.new] of State,
          fail_id,
          fail_id,
          [] of StateID,
          @utf8,
          @reverse,
          group_info,
          @look_matcher
        )
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
          replacement = case state.alternates.size
                        when 0
                          Fail.new.as(State)
                        when 1
                          next
                        when 2
                          BinaryUnion.new(state.alternates[0], state.alternates[1]).as(State)
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
    @look_set_prefix_all : Regex::Automata::LookSet
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
      @has_capture = compute_has_capture
      @has_empty = compute_has_empty
      @look_set_any = compute_look_set_any
      @look_set_prefix_any, @look_set_prefix_all = compute_prefix_look_sets
      @byte_classes = compute_byte_classes
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
      new([Fail.new] of State, fail_id, fail_id, [] of StateID, true, false, GroupInfo.empty)
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

    def look_set_prefix_all : Regex::Automata::LookSet
      @look_set_prefix_all
    end

    def byte_classes : Regex::Automata::ByteClasses
      @byte_classes
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
          # Match states have optional epsilon transition via next
          if next_id = state.next
            unless closure.includes?(next_id)
              closure.add(next_id)
              stack.push(next_id)
            end
          end
        when Fail, ByteRange, Sparse
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
                                  look_have.includes?(Regex::Automata::Look::WordAscii)
                                when Look::Kind::NonWordBoundaryAscii
                                  look_have.includes?(Regex::Automata::Look::WordAsciiNegate)
                                when Look::Kind::WordBoundaryUnicode
                                  look_have.includes?(Regex::Automata::Look::WordUnicode)
                                when Look::Kind::NonWordBoundaryUnicode
                                  look_have.includes?(Regex::Automata::Look::WordUnicodeNegate)
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
          # Match states have optional epsilon transition via next
          if next_id = state.next
            unless closure.includes?(next_id)
              closure.add(next_id)
              stack.push(next_id)
            end
          end
        when Fail, ByteRange, Sparse
          # No epsilon transitions
        end
      end

      closure
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
      end

      result
    end

    private def compute_has_capture : Bool
      @states.any?(&.is_a?(Capture))
    end

    private def state_memory_usage(state : State) : Int32
      case state
      when ByteRange, Look, BinaryUnion, Capture, Match, Fail, Empty
        0
      when Sparse
        (state.transitions.size * sizeof(Transition)).to_i32
      when Union
        (state.alternates.size * sizeof(StateID)).to_i32
      else
        0
      end
    end

    private def compute_byte_classes : Regex::Automata::ByteClasses
      signatures = {} of Array(Int32?) => UInt8
      mapping = Array.new(256, 0)
      next_class = 0

      256.times do |byte|
        byte_value = byte.to_u8
        signature = @states.map do |state|
          transition_target_for_byte(state, byte_value).try(&.to_i)
        end
        class_id = signatures[signature]?
        unless class_id
          class_id = next_class.to_u8
          signatures[signature] = class_id
          next_class += 1
        end
        mapping[byte] = class_id.to_i
      end

      Regex::Automata::ByteClasses.from_mapping(mapping, next_class)
    end

    private def compute_has_empty : Bool
      return false if @start_pattern.empty?

      @start_pattern.any? do |start_id|
        epsilon_closure(Set{start_id}).any? { |id| @states[id.to_i].is_a?(Match) }
      end
    end

    private def compute_look_set_any : Regex::Automata::LookSet
      @states.reduce(Regex::Automata::LookSet.empty) do |set, state|
        if state.is_a?(Look)
          set.union(look_from_kind(state.kind))
        else
          set
        end
      end
    end

    private def transition_target_for_byte(state : State, byte : UInt8) : StateID?
      case state
      when ByteRange
        state.trans.matches_byte(byte) ? state.trans.next : nil
      when Sparse
        state.matches_byte(byte)
      else
        nil
      end
    end

    private def compute_prefix_look_sets : Tuple(Regex::Automata::LookSet, Regex::Automata::LookSet)
      return {Regex::Automata::LookSet.empty, Regex::Automata::LookSet.empty} if @start_pattern.empty?

      any = Regex::Automata::LookSet.empty
      all : Regex::Automata::LookSet? = nil
      @start_pattern.each do |start_id|
        prefix = prefix_look_set(start_id)
        any = any.union(prefix)
        all = all ? all.not_nil!.intersect(prefix) : prefix
      end
      {any, all || Regex::Automata::LookSet.empty}
    end

    private def prefix_look_set(start_id : StateID) : Regex::Automata::LookSet
      stack = [start_id]
      visited = Set(StateID).new
      look_set = Regex::Automata::LookSet.empty

      until stack.empty?
        state_id = stack.pop
        next if visited.includes?(state_id)
        visited << state_id

        case state = @states[state_id.to_i]
        when Empty, Capture
          stack << state.next
        when Union
          state.alternates.each { |next_id| stack << next_id }
        when BinaryUnion
          stack << state.alt1
          stack << state.alt2
        when Look
          look_set = look_set.union(look_from_kind(state.kind))
          stack << state.next
        when Match
          stack << state.next.not_nil! if state.next
        when ByteRange, Sparse, Fail
        end
      end

      look_set
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
