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
    getter start_map : StartByteMap

    def initialize(@kind : StartKind, @unanchored : StateID, @anchored : StateID, unanchored_states : Hash(Start, StateID)? = nil, anchored_states : Hash(Start, StateID)? = nil, pattern_states : Hash(PatternID, Hash(Start, StateID))? = nil, @universal_start_unanchored : StateID? = nil, @universal_start_anchored : StateID? = nil, @dead : StateID = StateID.new(0), @start_map : StartByteMap = StartByteMap.new(LookMatcher.new))
      @unanchored_states = unanchored_states || default_states(@unanchored)
      @anchored_states = anchored_states || default_states(@anchored)
      @pattern_states = pattern_states || {} of PatternID => Hash(Start, StateID)
      @universal_start_unanchored ||= compute_universal_start(@unanchored_states, Anchored::No)
      @universal_start_anchored ||= compute_universal_start(@anchored_states, Anchored::Yes)
    end

    # Creates a well-formed start matrix whose every entry points at the dead
    # state. This mirrors Rust's construction-time placeholder before
    # determinization fills individual starts.
    def self.dead(kind : StartKind, look_matcher : LookMatcher, pattern_len : Int32? = nil) : StartTable
      if len = pattern_len
        raise BuildError.new("too many start states") if len < 0 || len.to_i64 > PatternID::MAX.as_u32.to_i64
      end
      dead = StateID::ZERO
      patterns = {} of PatternID => Hash(Start, StateID)
      (pattern_len || 0).times do |index|
        patterns[PatternID.new(index)] = default_states_for(dead)
      end
      StartTable.new(kind, dead, dead, default_states_for(dead), default_states_for(dead), patterns, nil, nil, dead, StartByteMap.new(look_matcher))
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

    # Writes the standalone dense start-table payload in Rust's field order:
    # kind, start-byte map, stride, optional pattern count, universal starts,
    # and fixed-order start IDs. Crystal owns the backing data, so this is a
    # direct write rather than a borrowing view.
    def write_to(dst : Bytes, endian : Symbol = :little) : Int32
      nwrite = write_to_len
      raise SerializeError.new("buffer too small for starting table ids") if dst.size < nwrite

      offset = 0
      write_u32(@kind.to_i.to_u32, dst, offset, endian)
      offset += 4
      offset += @start_map.write_to(dst[offset, @start_map.write_to_len])
      write_u32(Start.len.to_u32, dst, offset, endian)
      offset += 4
      pattern_len = @pattern_states.empty? ? UInt32::MAX : (@pattern_states.keys.max_by(&.to_i).to_i + 1).to_u32
      write_u32(pattern_len, dst, offset, endian)
      offset += 4
      write_u32(optional_state_id(@universal_start_unanchored), dst, offset, endian)
      offset += 4
      write_u32(optional_state_id(@universal_start_anchored), dst, offset, endian)
      offset += 4
      table.each do |id|
        write_u32(id.to_i.to_u32, dst, offset, endian)
        offset += 4
      end
      if pattern_len != UInt32::MAX
        pattern_len.to_i.times do |pattern_index|
          states = @pattern_states[PatternID.new(pattern_index)]?
          Start.each { |start| write_u32((states.try(&.[start]?) || @dead).to_i.to_u32, dst, offset, endian); offset += 4 }
        end
      end
      offset
    end

    def write_to_len : Int32
      4 + @start_map.write_to_len + 4 + 4 + 4 + 4 + ((12 + (pattern_wire_len * Start.len)) * 4)
    end

    # Reads Crystal-owned start-table data from the same standalone wire
    # payload written by #write_to. Unlike Rust's borrowed unchecked reader,
    # this validates every structural field and returns independent storage.
    def self.from_bytes(slice : Bytes, endian : Symbol = :little) : Tuple(StartTable, Int32)
      raise DeserializeError.new("buffer too small for starting table ids") if slice.size < 276
      offset = 0
      kind = case read_u32(slice, offset, endian)
             when 0 then StartKind::Both
             when 1 then StartKind::Unanchored
             when 2 then StartKind::Anchored
             else        raise DeserializeError.new("unrecognized start kind")
             end
      offset += 4
      start_map, nread = StartByteMap.from_bytes(slice[offset, slice.size - offset])
      offset += nread
      raise DeserializeError.new("invalid starting table stride") unless read_u32(slice, offset, endian) == Start.len
      offset += 4
      raw_pattern_len = read_u32(slice, offset, endian)
      offset += 4
      pattern_len = raw_pattern_len == UInt32::MAX ? 0 : raw_pattern_len.to_i
      raise DeserializeError.new("invalid number of patterns") if pattern_len > PatternID::LIMIT
      universal_unanchored = read_optional_state_id(slice, offset, endian, "universal unanchored start")
      offset += 4
      universal_anchored = read_optional_state_id(slice, offset, endian, "universal anchored start")
      offset += 4
      ids = Array(StateID).new(12 + pattern_len * Start.len)
      (12 + pattern_len * Start.len).times do
        ids << read_state_id(slice, offset, endian, "start ID")
        offset += 4
      end
      unanchored_states = {} of Start => StateID
      anchored_states = {} of Start => StateID
      Start.each do |start|
        unanchored_states[start] = ids[start.to_i]
        anchored_states[start] = ids[Start.len + start.to_i]
      end
      pattern_states = {} of PatternID => Hash(Start, StateID)
      pattern_len.times do |pattern_index|
        states = {} of Start => StateID
        Start.each { |start| states[start] = ids[(2 + pattern_index) * Start.len + start.to_i] }
        pattern_states[PatternID.new(pattern_index)] = states
      end
      {StartTable.new(kind, unanchored_states[Start::Text], anchored_states[Start::Text], unanchored_states, anchored_states, pattern_states, universal_unanchored, universal_anchored, StateID::ZERO, start_map), offset}
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
        @dead,
        @start_map
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
        (yield @dead),
        @start_map
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

    private def self.default_states_for(id : StateID) : Hash(Start, StateID)
      {
        Start::NonWordByte          => id,
        Start::WordByte             => id,
        Start::Text                 => id,
        Start::LineLF               => id,
        Start::LineCR               => id,
        Start::CustomLineTerminator => id,
      }
    end

    private def pattern_wire_len : Int32
      @pattern_states.empty? ? 0 : @pattern_states.keys.max_by(&.to_i).to_i + 1
    end

    private def optional_state_id(id : StateID?) : UInt32
      id ? id.not_nil!.to_i.to_u32 : UInt32::MAX
    end

    private def write_u32(value : UInt32, dst : Bytes, offset : Int32, endian : Symbol) : Nil
      if endian == :big
        4.times { |i| dst[offset + i] = ((value >> ((3 - i) * 8)) & 0xFF).to_u8 }
      else
        4.times { |i| dst[offset + i] = ((value >> (i * 8)) & 0xFF).to_u8 }
      end
    end

    private def self.read_u32(src : Bytes, offset : Int32, endian : Symbol) : UInt32
      raise DeserializeError.new("buffer too small for starting table ids") if offset < 0 || offset + 4 > src.size
      if endian == :big
        (0...4).reduce(0_u32) { |value, i| (value << 8) | src[offset + i].to_u32 }
      else
        (0...4).reduce(0_u32) { |value, i| value | (src[offset + i].to_u32 << (i * 8)) }
      end
    end

    private def self.read_state_id(src : Bytes, offset : Int32, endian : Symbol, label : String) : StateID
      value = read_u32(src, offset, endian)
      raise DeserializeError.new("invalid #{label}") if value > StateID::MAX.as_u32
      StateID.new(value.to_i32)
    end

    private def self.read_optional_state_id(src : Bytes, offset : Int32, endian : Symbol, label : String) : StateID?
      value = read_u32(src, offset, endian)
      return nil if value == UInt32::MAX
      raise DeserializeError.new("invalid #{label}") if value > StateID::MAX.as_u32
      StateID.new(value.to_i32)
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
