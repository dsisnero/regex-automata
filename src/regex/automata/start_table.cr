require "./errors"
require "./search"
require "./start_config"
require "./types"

module Regex::Automata
  enum Start
    NonWordByte
    WordByte
    Text
    LineLF
    LineCR
    CustomLineTerminator

    def self.len : Int32
      6
    end

    def self.from_usize(value : Int32) : Start?
      case value
      when 0 then NonWordByte
      when 1 then WordByte
      when 2 then Text
      when 3 then LineLF
      when 4 then LineCR
      when 5 then CustomLineTerminator
      else        nil
      end
    end

    def as_u8 : UInt8
      to_i.to_u8
    end

    def as_usize : Int32
      to_i32
    end
  end

  struct StartByteMap
    @map : StaticArray(Start, 256)

    def initialize(@map : StaticArray(Start, 256))
    end

    def self.new(lookm : LookMatcher) : StartByteMap
      map = StaticArray(Start, 256).new(Start::NonWordByte)
      map['\n'.ord] = Start::LineLF
      map['\r'.ord] = Start::LineCR
      map['_'.ord] = Start::WordByte

      ('0'.ord..'9'.ord).each { |byte| map[byte] = Start::WordByte }
      ('A'.ord..'Z'.ord).each { |byte| map[byte] = Start::WordByte }
      ('a'.ord..'z'.ord).each { |byte| map[byte] = Start::WordByte }

      lineterm = lookm.get_line_terminator
      if lineterm != '\r'.ord.to_u8 && lineterm != '\n'.ord.to_u8
        map[lineterm] = Start::CustomLineTerminator
      end
      StartByteMap.new(map)
    end

    def get(byte : UInt8) : Start
      @map[byte]
    end

    def self.from_bytes(slice : Bytes) : Tuple(StartByteMap, Int32)
      raise DeserializeError.new("buffer too small for start byte map") if slice.size < 256

      map = StaticArray(Start, 256).new(Start::NonWordByte)
      256.times do |index|
        start = Start.from_usize(slice[index].to_i)
        raise DeserializeError.new("found invalid starting configuration") unless start
        map[index] = start
      end
      {StartByteMap.new(map), 256}
    end

    def write_to(dst : Bytes) : Int32
      raise SerializeError.new("buffer too small for start byte map") if dst.size < write_to_len

      256.times { |index| dst[index] = @map[index].as_u8 }
      write_to_len
    end

    def write_to_len : Int32
      256
    end
  end

  # Dense DFA start state metadata.
  #
  # The Rust implementation stores a richer matrix of starts for different
  # contexts. This port currently models the anchored/unanchored start states
  # that the DFA builder materializes and centralizes the policy logic here so
  # the DFA API no longer reaches into raw instance variables directly.
  struct StartTable
    getter kind : StartKind
    getter dead : StateID
    getter unanchored : StateID
    getter anchored : StateID
    getter universal_start_unanchored : StateID?
    getter universal_start_anchored : StateID?
    getter unanchored_states : Hash(Start, StateID)
    getter anchored_states : Hash(Start, StateID)
    getter pattern_states : Hash(PatternID, Hash(Start, StateID))

    def initialize(@kind : StartKind, @unanchored : StateID, @anchored : StateID, unanchored_states : Hash(Start, StateID)? = nil, anchored_states : Hash(Start, StateID)? = nil, pattern_states : Hash(PatternID, Hash(Start, StateID))? = nil, @universal_start_unanchored : StateID? = nil, @universal_start_anchored : StateID? = nil, @dead : StateID = StateID.new(0))
      @unanchored_states = unanchored_states || default_states(@unanchored)
      @anchored_states = anchored_states || default_states(@anchored)
      @pattern_states = pattern_states || {} of PatternID => Hash(Start, StateID)
      @universal_start_unanchored ||= compute_universal_start(@unanchored_states, Anchored::No)
      @universal_start_anchored ||= compute_universal_start(@anchored_states, Anchored::Yes)
    end

    def start(anchored : Anchored) : StateID | StartError
      start(anchored, Start::Text, nil)
    end

    def start(anchored : Anchored, start : Start, pattern : PatternID? = nil) : StateID | StartError
      case anchored
      when Anchored::No
        return UnsupportedAnchoredStartError.new(anchored) if @kind == StartKind::Anchored
        @unanchored_states[start]? || @unanchored
      when Anchored::Yes
        return UnsupportedAnchoredStartError.new(anchored) if @kind == StartKind::Unanchored
        @anchored_states[start]? || @anchored
      when Anchored::Pattern
        return UnsupportedAnchoredStartError.new(anchored, pattern) unless pattern
        return UnsupportedAnchoredStartError.new(anchored, pattern) if @pattern_states.empty?
        states = @pattern_states[pattern]?
        return @dead unless states
        states[start]? || states[Start::Text]? || UnsupportedAnchoredStartError.new(anchored, pattern)
      else
        UnsupportedAnchoredStartError.new(anchored, pattern)
      end
    end

    def universal_start(anchored : Anchored) : StateID?
      case anchored
      when Anchored::No
        @universal_start_unanchored
      when Anchored::Yes
        @universal_start_anchored
      else
        nil
      end
    end

    def start_state?(id : StateID) : Bool
      @unanchored_states.values.includes?(id) ||
        @anchored_states.values.includes?(id) ||
        @pattern_states.values.any? { |states| states.values.includes?(id) }
    end

    # Snapshot every logical start state in Rust's table order. Crystal keeps
    # Anchored::Pattern and its PatternID as separate values, so the pattern
    # ID is returned as a fourth optional tuple member.
    def iter : Array(Tuple(StateID, Anchored, Start, PatternID?))
      entries = [] of Tuple(StateID, Anchored, Start, PatternID?)
      Start.len.times do |index|
        start = Start.from_usize(index).not_nil!
        entries << {(@unanchored_states[start]? || @unanchored), Anchored::No, start, nil}
      end
      Start.len.times do |index|
        start = Start.from_usize(index).not_nil!
        entries << {(@anchored_states[start]? || @anchored), Anchored::Yes, start, nil}
      end
      @pattern_states.keys.sort_by(&.to_i).each do |pattern_id|
        states = @pattern_states[pattern_id]
        Start.len.times do |index|
          start = Start.from_usize(index).not_nil!
          entries << {(states[start]? || states[Start::Text]? || @dead), Anchored::Pattern, start, pattern_id}
        end
      end
      entries
    end

    # Returns a snapshot of materialized state IDs in Rust table order.
    def table : Array(StateID)
      iter.map(&.[0])
    end

    # Validates that every materialized start can index the given transition
    # table and that none is a match state.
    def validate(tt : TransitionTable, &match_state : StateID -> Bool) : DeserializeError?
      if id = @universal_start_unanchored
        return DeserializeError.generic("found invalid universal unanchored starting state ID") unless tt.is_valid(id)
      end
      if id = @universal_start_anchored
        return DeserializeError.generic("found invalid universal anchored starting state ID") unless tt.is_valid(id)
      end
      table.each do |id|
        return DeserializeError.generic("found invalid starting state ID") unless tt.is_valid(id)
        return DeserializeError.generic("start states cannot be match states") if yield id
      end
      nil
    end

    # Logical StateID payload bytes, excluding Crystal Hash object overhead.
    def memory_usage : Int32
      (iter.size * sizeof(StateID)).to_i32
    end

    # Returns an independent owned copy suitable for DFA transformations.
    def to_owned : StartTable
      StartTable.new(
        @kind,
        @unanchored,
        @anchored,
        @unanchored_states.dup,
        @anchored_states.dup,
        @pattern_states.transform_values(&.dup),
        @universal_start_unanchored,
        @universal_start_anchored,
        @dead
      )
    end

    # Updates one materialized start state. Pattern-specific starts must have
    # been provisioned by the DFA builder, matching Rust's fixed table shape.
    def set_start(anchored : Anchored, start : Start, id : StateID, pattern : PatternID? = nil) : Nil
      case anchored
      when Anchored::No
        @unanchored_states[start] = id
        @unanchored = id if start == Start::Text
        @universal_start_unanchored = compute_universal_start(@unanchored_states, Anchored::No)
      when Anchored::Yes
        @anchored_states[start] = id
        @anchored = id if start == Start::Text
        @universal_start_anchored = compute_universal_start(@anchored_states, Anchored::Yes)
      when Anchored::Pattern
        raise ArgumentError.new("pattern ID is required for pattern start states") unless pattern
        states = @pattern_states[pattern]? || raise ArgumentError.new("pattern start states were not provisioned")
        states[start] = id
      else
        raise ArgumentError.new("unsupported anchored start mode")
      end
    end

    # Recomputes universal-start metadata after a bulk transformation.
    def refresh_universal_starts : Nil
      @universal_start_unanchored = compute_universal_start(@unanchored_states, Anchored::No)
      @universal_start_anchored = compute_universal_start(@anchored_states, Anchored::Yes)
    end

    def remap(&block : StateID -> StateID) : StartTable
      unanchored = yield @unanchored
      anchored = yield @anchored
      unanchored_states = @unanchored_states.transform_values { |id| yield id }
      anchored_states = @anchored_states.transform_values { |id| yield id }
      pattern_states = @pattern_states.transform_values do |states|
        states.transform_values { |id| yield id }
      end
      universal_unanchored = @universal_start_unanchored.try { |id| yield id }
      universal_anchored = @universal_start_anchored.try { |id| yield id }

      StartTable.new(
        @kind,
        unanchored,
        anchored,
        unanchored_states,
        anchored_states,
        pattern_states,
        universal_unanchored,
        universal_anchored,
        yield @dead
      )
    end

    def self.from_look_behind(byte : UInt8?) : Start
      return Start::Text if byte.nil?

      StartByteMap.new(LookMatcher.new).get(byte)
    end

    private def default_states(id : StateID) : Hash(Start, StateID)
      {
        Start::NonWordByte          => id,
        Start::WordByte             => id,
        Start::Text                 => id,
        Start::LineLF               => id,
        Start::LineCR               => id,
        Start::CustomLineTerminator => id,
      }
    end

    private def compute_universal_start(states : Hash(Start, StateID), anchored : Anchored) : StateID?
      case anchored
      when Anchored::No
        return nil if @kind == StartKind::Anchored
      when Anchored::Yes
        return nil if @kind == StartKind::Unanchored
      else
        return nil
      end

      ids = states.values.uniq
      ids.size == 1 ? ids.first : nil
    end
  end
end
