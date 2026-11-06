require "./automaton"
require "./dfa"

module Regex::Automata::DFA::Sparse
  # Stack-allocated view into a validated packed state, matching sparse.rs::State.
  # :nodoc:
  struct State
    getter id : StateID
    getter ntrans : Int32
    getter ranges : Bytes
    getter targets : Bytes
    getter patterns : Bytes
    getter accel : Bytes
    getter? match : Bool

    def initialize(bytes : Bytes, @id : StateID)
      offset = id.to_i
      header = Wire.read_u16(bytes[offset, 2])
      @match = header & 0x8000_u16 != 0
      @ntrans = (header & 0x7FFF_u16).to_i
      offset += 2
      @ranges = bytes[offset, @ntrans * 2]
      offset += @ntrans * 2
      @targets = bytes[offset, @ntrans * 4]
      offset += @ntrans * 4
      if @match
        length = Wire.read_u32(bytes[offset, 4]).to_i
        offset += 4
        @patterns = bytes[offset, length * 4]
        offset += length * 4
      else
        @patterns = Bytes.empty
      end
      length = bytes[offset].to_i
      @accel = bytes[offset + 1, length]
    end

    def next_at(index : Int32) : StateID
      StateID.new(Wire.read_u32(@targets[index * 4, 4]).to_i32)
    end

    def next(input : UInt8) : StateID
      (@ntrans - 1).times do |index|
        return next_at(index) if @ranges[index * 2] <= input <= @ranges[index * 2 + 1]
      end
      StateID::ZERO
    end

    def pattern_len : Int32
      @patterns.size // 4
    end

    def pattern(index : Int32) : PatternID
      PatternID.new(Wire.read_u32(@patterns[index * 4, 4]).to_i32)
    end

    def write_to_len : Int32
      3 + @ntrans * 6 + @accel.size + (@match ? 4 + @patterns.size : 0)
    end

    def write_to(dst : Bytes, endian : Symbol) : Int32
      raise SerializeError.buffer_too_small("sparse state transitions") if dst.size < write_to_len
      offset = Wire.write_u16(@ntrans.to_u16 | (@match ? 0x8000_u16 : 0_u16), dst, endian)
      dst[offset, @ranges.size].copy_from(@ranges)
      offset += @ranges.size
      @ntrans.times { |index| offset += Wire.write_state_id(next_at(index), dst[offset..], endian) }
      if @match
        offset += Wire.write_u32(pattern_len.to_u32, dst[offset..], endian)
        pattern_len.times { |index| offset += Wire.write_pattern_id(pattern(index), dst[offset..], endian) }
      end
      dst[offset] = @accel.size.to_u8
      dst[offset + 1, @accel.size].copy_from(@accel)
      offset + 1 + @accel.size
    end
  end

  # Packed native start IDs; no Hash lookup or allocation on start-state queries.
  # :nodoc:
  struct StartTable
    getter kind : StartKind
    getter start_map : StartByteMap
    getter pattern_len : Int32?
    getter universal_unanchored : StateID?
    getter universal_anchored : StateID?
    getter table : Bytes

    def initialize(@kind : StartKind, @start_map : StartByteMap, @pattern_len : Int32?, @universal_unanchored : StateID?, @universal_anchored : StateID?, @table : Bytes)
    end

    def self.from_dense(dense : ::Regex::Automata::DFA::DFA, remap : Array(StateID)) : StartTable
      ids = dense.st.table
      bytes = Bytes.new(ids.size * 4)
      ids.each_with_index { |id, index| Wire.write_state_id(remap[dense.to_index(id)], bytes[index * 4, 4]) }
      new(dense.start_kind, dense.start_map, dense.st.pattern_len,
        dense.universal_start_state(Anchored::No).try { |id| remap[dense.to_index(id)] },
        dense.universal_start_state(Anchored::Yes).try { |id| remap[dense.to_index(id)] }, bytes)
    end

    def self.from_bytes(reader : WireReader) : StartTable
      kind = case reader.u32("start kind")
             when 0 then StartKind::Both
             when 1 then StartKind::Unanchored
             when 2 then StartKind::Anchored
             else        raise DeserializeError.generic("unrecognized start kind")
             end
      start_map, read = StartByteMap.from_bytes(reader.rest)
      reader.take(read, "start byte map")
      raise DeserializeError.generic("invalid sparse starting table stride") unless reader.u32("sparse start table stride") == Start.len
      raw = reader.u32("sparse start table patterns")
      raise DeserializeError.generic("sparse invalid number of patterns") if raw != UInt32::MAX && raw > PatternID::LIMIT.to_u32
      patterns = raw == UInt32::MAX ? nil : raw.to_i32
      universal_unanchored = optional_id(reader.u32("universal unanchored start"))
      universal_anchored = optional_id(reader.u32("universal anchored start"))
      count = patterns || 0
      raise DeserializeError.buffer_too_small("sparse start ID table") if count > (reader.rest.size - 48) // (Start.len * 4)
      table = reader.take((2 + count) * Start.len * 4, "sparse start ID table").dup
      new(kind, start_map, patterns, universal_unanchored, universal_anchored, table)
    end

    private def self.optional_id(raw : UInt32) : StateID?
      return nil if raw == UInt32::MAX
      raise DeserializeError.generic("invalid universal start state ID") if raw > StateID::MAX.as_u32
      StateID.new(raw.to_i32)
    end

    def start(config : StartConfig) : StateID | StartError
      start = config.look_behind.try { |byte| @start_map.get(byte) } || Start::Text
      index = case config.anchored
              when Anchored::No
                return UnsupportedAnchoredStartError.new(config.anchored) if @kind == StartKind::Anchored
                start.to_i
              when Anchored::Yes
                return UnsupportedAnchoredStartError.new(config.anchored) if @kind == StartKind::Unanchored
                Start.len + start.to_i
              when Anchored::Pattern
                return UnsupportedAnchoredStartError.new(config.anchored, config.pattern) unless length = @pattern_len
                return UnsupportedAnchoredStartError.new(config.anchored, config.pattern) unless pattern = config.pattern
                return StateID::ZERO if pattern.to_i >= length
                (2 + pattern.to_i) * Start.len + start.to_i
              else
                return UnsupportedAnchoredStartError.new(config.anchored, config.pattern)
              end
      StateID.new(Wire.read_u32(@table[index * 4, 4]).to_i32)
    end

    def to_owned : StartTable
      StartTable.new(@kind, @start_map, @pattern_len, @universal_unanchored, @universal_anchored, @table.dup)
    end

    def write_to_len : Int32
      276 + @table.size
    end

    def write_to(dst : Bytes, endian : Symbol) : Int32
      raise SerializeError.buffer_too_small("sparse starting table ids") if dst.size < write_to_len
      offset = Wire.write_u32(@kind.to_i.to_u32, dst, endian)
      offset += @start_map.write_to(dst[offset..])
      offset += Wire.write_u32(Start.len.to_u32, dst[offset..], endian)
      offset += Wire.write_u32(@pattern_len.try(&.to_u32) || UInt32::MAX, dst[offset..], endian)
      offset += Wire.write_u32(@universal_unanchored.try(&.as_u32) || UInt32::MAX, dst[offset..], endian)
      offset += Wire.write_u32(@universal_anchored.try(&.as_u32) || UInt32::MAX, dst[offset..], endian)
      (@table.size // 4).times do |index|
        offset += Wire.write_u32(Wire.read_u32(@table[index * 4, 4]), dst[offset..], endian)
      end
      offset
    end
  end

  # Rust's sparse DFA: variable-size states with byte-offset StateIDs.
  class DFA < ::Regex::Automata::Automaton
    LABEL   = "rust-regex-automata-dfa-sparse"
    VERSION = 2_u32

    getter byte_classes : ByteClasses
    getter state_len : Int32
    getter pattern_len : Int32
    getter special : Special

    def initialize(@packed : Bytes, @byte_classes : ByteClasses, @state_len : Int32, @pattern_len : Int32, @starts : StartTable, @special : Special, @prefilter : Prefilter?, @quitset : ByteSet, @flags : DFAFlags)
    end

    def self.new(pattern : String) : DFA
      from_dense(::Regex::Automata::DFA::DFA.new(pattern))
    end

    def self.new_many(patterns : Array(String)) : DFA
      from_dense(::Regex::Automata::DFA::DFA.new_many(patterns))
    end

    def self.always_match : DFA
      from_dense(::Regex::Automata::DFA::DFA.always_match)
    end

    def self.never_match : DFA
      from_dense(::Regex::Automata::DFA::DFA.never_match)
    end

    def self.from_dense(dense : ::Regex::Automata::DFA::DFA) : DFA
      output = IO::Memory.new
      remap = Array(StateID).new(dense.state_len, StateID::ZERO)
      dense.states.each_with_index do |state, index|
        raise BuildError.too_many_states if output.size.to_i64 > StateID::MAX.as_u32.to_i64
        remap[index] = StateID.new(output.size.to_i32)
        runs = state.sparse_transitions
        count = runs.size + 1 # Always reserve a final dummy EOI pair/target.
        matching = dense.is_match_state?(state.id)
        output.write_bytes(count.to_u16 | (matching ? 0x8000_u16 : 0_u16), IO::ByteFormat::SystemEndian)
        runs.each { |first, last, _| output.write_byte(first.to_u8); output.write_byte(last.to_u8) }
        output.write_bytes(0_u16, IO::ByteFormat::SystemEndian)
        count.times { output.write_bytes(0_u32, IO::ByteFormat::SystemEndian) }
        if matching
          patterns = dense.pattern_id_slice(state.id)
          output.write_bytes(patterns.size.to_u32, IO::ByteFormat::SystemEndian)
          patterns.each { |pattern| output.write_bytes(pattern.as_u32, IO::ByteFormat::SystemEndian) }
        end
        accelerator = dense.accelerator(state.id)
        output.write_byte(accelerator.size.to_u8)
        output.write(accelerator)
      end
      packed = output.to_slice.dup
      dense.states.each_with_index do |state, index|
        runs = state.sparse_transitions
        offset = remap[index].to_i + 2 + (runs.size + 1) * 2
        runs.each do |_, _, target|
          offset += Wire.write_state_id(remap[dense.to_index(target)], packed[offset..])
        end
        Wire.write_state_id(remap[dense.to_index(state.eoi_next)], packed[offset..])
      end
      quitset = ByteSet.new
      dense.quitset.each { |byte| quitset.add(byte) }
      new(packed, dense.byte_classifier, dense.state_len, dense.pattern_len,
        StartTable.from_dense(dense, remap), dense.special.remap { |id| remap[dense.to_index(id)] },
        dense.get_prefilter, quitset, dense.flags)
    end

    def self.from_bytes(bytes : Bytes) : Tuple(DFA, Int32)
      reader = WireReader.new(bytes)
      reader.take(Wire.read_label(reader.rest, LABEL), "label")
      reader.take(Wire.read_endianness_check(reader.rest), "endianness")
      reader.take(Wire.read_version(reader.rest, VERSION), "version")
      reader.u32("unused space")
      bits = reader.u32("flag bitset")
      state_len = reader.count("state length")
      pattern_len = reader.count("pattern length")
      classes, read = ByteClasses.from_bytes(reader.rest)
      reader.take(read, "byte class map")
      length = reader.count("sparse transitions length")
      packed = reader.take(length, "sparse states byte length").dup
      starts = StartTable.from_bytes(reader)
      ids = Array.new(8) { reader.id("special state ID") }
      special = Special.new(ids[0], ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], ids[7])
      if error = special.validate
        raise error
      end
      raise DeserializeError.generic("max should not be greater than or equal to sparse bytes") if special.max.to_i >= packed.size
      raw_quit = reader.take(32, "byte set")
      quit = Bytes.new(32)
      # Preserve the pinned low-u128-bucket-twice reader, as in dense wire.
      low = Wire.read_u128(raw_quit[0, 16])
      2.times { |index| IO::ByteFormat::LittleEndian.encode(low, quit[index * 16, 16]) }
      quitset, _ = ByteSet.from_bytes(quit)
      flags = DFAFlags.new(has_empty: bits.bit(0) == 1, is_utf8: bits.bit(1) == 1,
        is_always_start_anchored: bits.bit(2) == 1)
      dfa = new(packed, classes, state_len, pattern_len, starts, special, nil, quitset, flags)
      dfa.validate
      {dfa, reader.offset}
    end

    # Crystal cannot expose Rust's unsafe borrowed storage; validate owned bytes.
    def self.from_bytes_unchecked(bytes : Bytes) : Tuple(DFA, Int32)
      from_bytes(bytes)
    end

    protected def validate : Nil
      seen = Set(StateID).new
      offset = 0
      while offset < @packed.size
        id = StateID.new(offset)
        if is_special_state?(id) && !is_dead_state?(id) && !is_quit_state?(id) && !is_match_state?(id) && !is_start_state?(id) && !is_accel_state?(id)
          raise DeserializeError.generic("found sparse state tagged as special but wasn't actually special")
        end
        offset += validate_state(id)
        seen.add(id)
      end
      offset = 0
      while offset < @packed.size
        state = State.new(@packed, StateID.new(offset))
        state.ntrans.times do |index|
          raise DeserializeError.generic("found transition that points to a non-existent state") unless seen.includes?(state.next_at(index))
        end
        offset += state.write_to_len
      end
      raise DeserializeError.generic("mismatching sparse state length") unless seen.size == @state_len
      (@starts.table.size // 4).times do |index|
        raw = Wire.read_u32(@starts.table[index * 4, 4])
        raise DeserializeError.generic("found invalid starting state ID") if raw > StateID::MAX.as_u32
        id = StateID.new(raw.to_i32)
        raise DeserializeError.generic("found invalid starting state ID") unless seen.includes?(id)
        raise DeserializeError.generic("start states cannot be match states") if is_match_state?(id)
      end
    end

    private def validate_state(id : StateID) : Int32
      reader = WireReader.new(@packed[id.to_i..])
      header = Wire.read_u16(reader.take(2, "state transition length"))
      matching = header & 0x8000_u16 != 0
      count = (header & 0x7FFF_u16).to_i
      raise DeserializeError.generic("invalid transition length") unless 1 <= count <= 257
      raise DeserializeError.generic("whether state is a match or not is inconsistent") unless matching == is_match_state?(id)
      ranges = reader.take(count * 2, "sparse byte pairs")
      count.times do |index|
        raise DeserializeError.generic("invalid input range") if ranges[index * 2] > ranges[index * 2 + 1]
      end
      targets = reader.take(count * 4, "sparse trans state IDs")
      count.times do |index|
        raw = Wire.read_u32(targets[index * 4, 4])
        raise DeserializeError.generic("invalid sparse state ID") if raw > StateID::MAX.as_u32 || raw > @packed.size.to_u32
      end
      if matching
        patterns = reader.count("pattern ID length")
        raise DeserializeError.generic("state marked as a match, but pattern length is zero") if patterns == 0
        raise DeserializeError.buffer_too_small("sparse pattern IDs") if patterns > reader.rest.size // 4
        patterns.times do
          raw = reader.u32("sparse pattern ID")
          raise DeserializeError.generic("invalid sparse pattern ID") if raw > PatternID::MAX.as_u32
        end
      end
      accel_len = reader.take(1, "no accelerator length")[0].to_i
      raise DeserializeError.generic("sparse invalid accelerator length") if accel_len > 3
      raise DeserializeError.generic("got no accelerators in state, but in accelerator ID range") if accel_len == 0 && is_accel_state?(id)
      raise DeserializeError.generic("state in accelerator ID range, but has no accelerators") if accel_len > 0 && !is_accel_state?(id)
      reader.take(accel_len, "sparse corrupt accelerator length")
      raise DeserializeError.generic("state with EOI transition to quit state is illegal") if is_quit_state?(StateID.new(Wire.read_u32(targets[(count - 1) * 4, 4]).to_i32))
      reader.offset
    end

    # Crystal inspection summarizes the native packed object; Rust's Debug
    # trait and its private formatting iterator types are not retained.
    def inspect(io : IO) : Nil
      io << "Regex::Automata::DFA::Sparse::DFA(states: " << @state_len
      io << ", patterns: " << @pattern_len << ", memory: " << memory_usage << ")"
    end

    def as_ref : DFA
      DFA.new(@packed, @byte_classes, @state_len, @pattern_len, @starts, @special, @prefilter, @quitset, @flags)
    end

    def to_owned : DFA
      quitset = ByteSet.new
      @quitset.each { |byte| quitset.add(byte) }
      DFA.new(@packed.dup, @byte_classes, @state_len, @pattern_len, @starts.to_owned, @special, @prefilter, quitset, @flags)
    end

    def to_sparse : DFA
      self
    end

    def start_kind : StartKind
      @starts.kind
    end

    def starts_for_each_pattern? : Bool
      !@starts.pattern_len.nil?
    end

    # Compatibility spelling retained for existing Crystal callers.
    def starts_for_each_pattern : Bool
      starts_for_each_pattern?
    end

    def memory_usage : Int32
      @packed.size + @starts.table.size
    end

    def set_prefilter(@prefilter : Prefilter?) : Nil
    end

    def get_prefilter : Prefilter?
      @prefilter
    end

    def next_state(current : StateID, input : UInt8) : StateID
      State.new(@packed, current).next(@byte_classes.get(input))
    end

    def next_state_unchecked(current : StateID, input : UInt8) : StateID
      next_state(current, input)
    end

    def next_eoi_state(current : StateID) : StateID
      state = State.new(@packed, current)
      state.next_at(state.ntrans - 1)
    end

    def start_state(config : StartConfig) : StateID | StartError
      if byte = config.look_behind
        return QuitStartError.new(byte) if @quitset.includes?(byte)
      end
      @starts.start(config)
    end

    # Compatibility with the inherited Crystal anchored convenience method.
    def start_state_forward_method(anchored : Anchored) : StateID
      result = start_state(StartConfig.new(nil, anchored))
      result.is_a?(StateID) ? result : search_start_state
    end

    def is_special_state?(id : StateID) : Bool
      @special.is_special_state?(id)
    end

    def is_dead_state?(id : StateID) : Bool
      @special.is_dead_state?(id)
    end

    def is_quit_state?(id : StateID) : Bool
      @special.is_quit_state?(id)
    end

    def is_match_state?(id : StateID) : Bool
      @special.is_match_state?(id)
    end

    def is_start_state?(id : StateID) : Bool
      @special.is_start_state?(id)
    end

    def is_accel_state?(id : StateID) : Bool
      @special.is_accel_state?(id)
    end

    def match_len(id : StateID) : Int32
      State.new(@packed, id).pattern_len
    end

    def match_pattern(id : StateID, index : Int32) : PatternID
      return PatternID::ZERO if @pattern_len == 1
      State.new(@packed, id).pattern(index)
    end

    def has_empty? : Bool
      @flags.has_empty
    end

    def is_utf8? : Bool
      @flags.is_utf8
    end

    def is_always_start_anchored? : Bool
      @flags.is_always_start_anchored
    end

    def accelerator(id : StateID) : Bytes
      State.new(@packed, id).accel
    end

    def universal_start_state(mode : Anchored) : StateID?
      case mode
      when Anchored::No  then @starts.universal_unanchored
      when Anchored::Yes then @starts.universal_anchored
      else                    nil
      end
    end

    def to_bytes_little_endian : Bytes
      to_bytes(:little)
    end

    def to_bytes_big_endian : Bytes
      to_bytes(:big)
    end

    def to_bytes_native_endian : Bytes
      to_bytes(:native)
    end

    private def to_bytes(endian : Symbol) : Bytes
      bytes = Bytes.new(write_to_len)
      write_to(bytes, endian)
      bytes
    end

    def write_to_little_endian(dst : Bytes) : Int32
      write_to(dst, :little)
    end

    def write_to_big_endian(dst : Bytes) : Int32
      write_to(dst, :big)
    end

    def write_to_native_endian(dst : Bytes) : Int32
      write_to(dst, :native)
    end

    def write_to_len : Int32
      48 + 268 + @packed.size + @starts.write_to_len + 32 + 32
    end

    private def write_to(dst : Bytes, endian : Symbol) : Int32
      raise SerializeError.buffer_too_small("sparse DFA") if dst.size < write_to_len
      offset = Wire.write_label(LABEL, dst)
      offset += Wire.write_endianness_check(dst[offset..], endian)
      offset += Wire.write_version(VERSION, dst[offset..], endian)
      offset += Wire.write_u32(0_u32, dst[offset..], endian)
      bits = (@flags.has_empty ? 1_u32 : 0_u32) | (@flags.is_utf8 ? 2_u32 : 0_u32) | (@flags.is_always_start_anchored ? 4_u32 : 0_u32)
      offset += Wire.write_u32(bits, dst[offset..], endian)
      offset += Wire.write_u32(@state_len.to_u32, dst[offset..], endian)
      offset += Wire.write_u32(@pattern_len.to_u32, dst[offset..], endian)
      offset += @byte_classes.write_to(dst[offset..])
      offset += Wire.write_u32(@packed.size.to_u32, dst[offset..], endian)
      state_offset = 0
      while state_offset < @packed.size
        state = State.new(@packed, StateID.new(state_offset))
        offset += state.write_to(dst[offset..], endian)
        state_offset += state.write_to_len
      end
      offset += @starts.write_to(dst[offset..], endian)
      sp = @special
      {sp.max, sp.quit_id, sp.min_match, sp.max_match, sp.min_accel, sp.max_accel, sp.min_start, sp.max_start}.each do |id|
        offset += Wire.write_state_id(id, dst[offset..], endian)
      end
      quit = @quitset.to_bytes
      2.times do |index|
        value = IO::ByteFormat::LittleEndian.decode(UInt128, quit[index * 16, 16])
        offset += Wire.write_u128(value, dst[offset..], endian)
      end
      offset
    end

    def try_search_fwd(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError
      last_match : Tuple(Int32, Array(PatternID))? = nil
      start_state_id = search_start_state
      current_state_id = start_state_id
      if is_match_state?(current_state_id)
        last_match = {0, state_matches(current_state_id)}
      end

      idx = 0
      size = slice.size

      while idx < size
        byte = slice[idx]
        next_state_id = next_state(current_state_id, slice[idx])

        if is_quit_state?(next_state_id)
          return MatchError.quit(byte, idx)
        end

        break if is_dead_state?(next_state_id)

        current_state_id = next_state_id
        if is_match_state?(current_state_id)
          last_match = {idx, state_matches(current_state_id)}
        end
        idx += 1
        if is_accel_state?(current_state_id)
          idx = Regex::Automata.find_fwd(accelerator(current_state_id), slice, idx) || size
        end
      end

      if idx == size
        eoi_state = next_eoi_state(current_state_id)
        if is_match_state?(eoi_state)
          last_match = {size, state_matches(eoi_state)}
        elsif is_quit_state?(eoi_state)
          return MatchError.quit(0_u8, size)
        end
      end

      last_match
    end

    # Try to search in reverse, returning either a match or a MatchError
    def try_search_rev(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError
      last_match : Tuple(Int32, Array(PatternID))? = nil
      start_state_id = search_start_state
      current_state_id = start_state_id

      idx = slice.size - 1

      while idx >= 0
        byte = slice[idx]
        next_state_id = next_state(current_state_id, byte)

        if ENV["LOGOS_DEBUG_DFA_SEARCH"]?
          puts "Reverse search: idx=#{idx}, byte=#{byte}, current_state=#{current_state_id.to_i}, next_state=#{next_state_id.to_i}"
        end

        return MatchError.quit(byte, idx) if is_quit_state?(next_state_id)

        break if is_dead_state?(next_state_id)

        current_state_id = next_state_id
        if is_match_state?(current_state_id)
          last_match = {idx + 1, state_matches(current_state_id)}
        end
        idx -= 1
        if is_accel_state?(current_state_id)
          idx = Regex::Automata.find_rev(accelerator(current_state_id), slice, idx + 1) || -1
        end
      end

      if idx < 0
        eoi_state = next_eoi_state(current_state_id)
        if is_match_state?(eoi_state)
          last_match = {0, state_matches(eoi_state)}
        elsif is_quit_state?(eoi_state)
          return MatchError.quit(0_u8, 0)
        end
      end

      last_match
    end

    def try_search_overlapping_fwd(slice : Bytes) : Array(Tuple(Int32, Array(PatternID))) | MatchError
      matches_by_offset = {} of Int32 => Array(PatternID)
      size = slice.size

      (0..size).each do |start|
        input = Input.new(slice).span(start...size).anchored(Anchored::Yes)
        state = OverlappingState.start
        current_offset = nil.as(Int32?)
        current_patterns = [] of PatternID

        loop do
          result = try_search_overlapping_fwd(input, state)
          return result if result.is_a?(MatchError)

          half_match = state.get_match
          unless half_match
            if offset = current_offset
              merge_overlapping_patterns(matches_by_offset, offset, current_patterns)
            end
            break
          end

          if current_offset == half_match.offset
            current_patterns << half_match.pattern unless current_patterns.includes?(half_match.pattern)
          else
            if offset = current_offset
              merge_overlapping_patterns(matches_by_offset, offset, current_patterns)
            end
            current_offset = half_match.offset
            current_patterns = [half_match.pattern]
          end
        end
      end

      matches_by_offset.keys.sort.map { |offset| {offset, matches_by_offset[offset]} }
    end

    private def state_matches(id : StateID) : Array(PatternID)
      Array.new(match_len(id)) { |index| match_pattern(id, index) }
    end

    private def search_start_state : StateID
      config = StartConfig.new(nil, start_kind == StartKind::Anchored ? Anchored::Yes : Anchored::No)
      @starts.start(config).as(StateID)
    end

    private def merge_overlapping_patterns(matches : Hash(Int32, Array(PatternID)), offset : Int32, patterns : Array(PatternID)) : Nil
      target = matches[offset] ||= [] of PatternID
      patterns.each { |pattern| target << pattern unless target.includes?(pattern) }
    end
  end
end

module Regex::Automata::DFA
  class DFA
    def to_sparse : Sparse::DFA
      Sparse::DFA.from_dense(self)
    end
  end
end
