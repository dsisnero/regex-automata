require "./wire"

module Regex::Automata::DFA
  # A bounded native-endian reader. Counts are checked against the remaining
  # bytes before allocating owned arrays, including for untrusted fuzz inputs.
  class WireReader
    getter offset : Int32 = 0

    def initialize(@bytes : Bytes)
    end

    def take(length : Int32, what : String) : Bytes
      raise DeserializeError.buffer_too_small(what) if length < 0 || length > @bytes.size - @offset
      bytes = @bytes[@offset, length]
      @offset += length
      bytes
    end

    def rest : Bytes
      @bytes[@offset, @bytes.size - @offset]
    end

    def u32(what : String) : UInt32
      Wire.read_u32(take(4, what))
    end

    def count(what : String) : Int32
      value = u32(what)
      raise DeserializeError.invalid_usize(what) if value > Int32::MAX.to_u32
      value.to_i32
    end

    def id(what : String) : StateID
      value = u32(what)
      raise DeserializeError.generic("invalid #{what}") if value > StateID::MAX.as_u32
      StateID.new(value.to_i32)
    end
  end

  class DFA
    @wire_accels : Bytes? = nil
    @wire_padding : Hash(Int32, UInt32)? = nil

    WIRE_LABEL   = "rust-regex-automata-dfa-dense"
    WIRE_VERSION = 2_u32

    # Native Rust v2 decoding owns its tables in Crystal. Alignment and native
    # endianness are still checked exactly as for Rust's borrowed decoder.
    def self.from_bytes(bytes : Bytes) : Tuple(DFA, Int32)
      reader = WireReader.new(bytes)
      reader.take(Wire.skip_initial_padding(bytes), "initial padding")
      Wire.check_alignment(reader.rest, 4)
      reader.take(Wire.read_label(reader.rest, WIRE_LABEL), "label")
      reader.take(Wire.read_endianness_check(reader.rest), "endianness check")
      reader.take(Wire.read_version(reader.rest, WIRE_VERSION), "version")
      reader.u32("unused space")
      bits = reader.u32("flag bitset")
      state_len = reader.count("state length")
      stride2 = reader.count("stride2")
      raise DeserializeError.generic("dense DFA has invalid stride2 (too big)") if stride2 > 9
      raise DeserializeError.generic("dense DFA has invalid stride2 (too small)") if stride2 < 1
      classes, read = ByteClasses.from_bytes(reader.rest)
      reader.take(read, "byte class map")
      stride = 1 << stride2
      raise DeserializeError.generic("alphabet size cannot be bigger than transition table stride") if classes.alphabet_len > stride
      # Bound the product before multiplying or reserving any state storage.
      raise DeserializeError.buffer_too_small("transition table") if state_len > reader.rest.size // (stride * 4)
      tt = TransitionTable.new(classes, stride2)
      padding = nil.as(Hash(Int32, UInt32)?)
      (state_len * stride).times do |index|
        value = reader.u32("transition table state ID")
        if index % stride >= classes.alphabet_len
          # Rust ignores stride padding during validation but retains its raw
          # u32 bits. Keep them apart from Crystal's checked StateID values.
          if value != 0
            saved = padding ||= {} of Int32 => UInt32
            saved[index] = value
          end
          tt.table << StateID::ZERO
        else
          raise DeserializeError.generic("found invalid state ID in transition table") if value > StateID::MAX.as_u32
          tt.table << StateID.new(value.to_i32)
        end
      end
      endian = native_wire_endian
      starts, read = StartTable.from_bytes(reader.rest, endian)
      reader.take(read, "start table")
      matches, read = MatchStates.from_bytes(reader.rest, endian)
      reader.take(read, "match states")
      ids = Array.new(8) { reader.id("special state ID") }
      special = Special.new(ids[0], ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], ids[7])
      if error = special.validate
        raise error
      end
      if error = special.validate_state_len(state_len, stride2)
        raise error
      end
      accel_len = reader.count("accelerators length")
      raise DeserializeError.buffer_too_small("accelerators") if accel_len > reader.rest.size // 8
      accel_bytes = reader.take(accel_len * 8, "accelerators")
      (accel_len * 2).times do |index|
        raise DeserializeError.generic("accelerator bytes cannot have length more than 3") if accel_bytes[index * 4] > 3
      end
      quit_bytes = reader.take(32, "quit bytes")
      normalized_quit_bytes = Bytes.new(32)
      2.times do |index|
        # Pinned alphabet.rs::ByteSet::from_bytes reads both buckets
        # from the low-bucket slice. Preserve its observable behavior.
        word = Wire.read_u128(quit_bytes[0, 16])
        IO::ByteFormat::LittleEndian.encode(word, normalized_quit_bytes[index * 16, 16])
      end
      quitset, _ = ByteSet.from_bytes(normalized_quit_bytes)

      # Rust validates match slices before transitions and starts. Do not index
      # a slice based on the special range until the two lengths agree.
      match_count = special.matches? ? ((special.max_match.to_i - special.min_match.to_i) // stride + 1) : 0
      raise DeserializeError.generic("match state length mismatch") unless matches.slices.size == match_count
      if error = matches.validate
        raise error
      end
      pattern_ids = matches.pattern_ids
      match_map = {} of StateID => Array(PatternID)
      matches.slices.each_with_index do |(start, length), index|
        raise DeserializeError.generic("invalid pattern ID start offset") if start >= pattern_ids.size
        id = StateID.new(special.min_match.to_i + index * stride)
        match_map[id] = pattern_ids[start, length]
      end
      states = Array.new(state_len) do |index|
        id = tt.to_state_id(index)
        if special.is_special_state?(id)
          unless special.is_dead_state?(id) || special.is_quit_state?(id) || special.is_match_state?(id) || special.is_start_state?(id) || special.is_accel_state?(id)
            raise DeserializeError.generic("found dense state tagged as special but wasn't actually special")
          end
          if special.is_match_state?(id) && (match_map[id]?.try(&.empty?) != false)
            raise DeserializeError.generic("found match state with zero pattern IDs")
          end
        end
        state = State.new(StateID.new(index), classes.alphabet_len - 1)
        state.next = Array.new(classes.alphabet_len - 1) { |unit| StateID.new(tt.to_index(tt.next_state_by_class(id, unit))) }
        state.eoi_next = StateID.new(tt.to_index(tt.next_eoi_state(id)))
        state.match = match_map[id]? || [] of PatternID
        state
      end
      # Check every logical transition including EOI, before constructing a
      # normalized graph or consulting any start-state ID.
      state_len.times do |index|
        id = tt.to_state_id(index)
        classes.alphabet_len.times do |unit|
          raise DeserializeError.generic("found invalid state ID in transition table") unless tt.is_valid(tt.next_state_by_class(id, unit))
        end
      end
      if error = starts.validate(tt) { |id| special.is_match_state?(id) }
        raise error
      end
      accelerators = Array.new(state_len) { Bytes.empty }
      state_len.times do |index|
        id = tt.to_state_id(index)
        next unless special.is_accel_state?(id)
        accel_index = (id.to_i - special.min_accel.to_i) // stride
        raise DeserializeError.generic("found DFA state with invalid accelerator index") unless 0 <= accel_index < accel_len
        length = accel_bytes[accel_index * 8].to_i
        raise DeserializeError.generic("accelerator needles has invalid length") unless 1 <= length <= 3
        accelerators[index] = accel_bytes[accel_index * 8 + 1, length].dup
      end
      flags = DFAFlags.new(premultiplied: true, has_empty: bits.bit(0) == 1, is_utf8: bits.bit(1) == 1,
        is_always_start_anchored: bits.bit(2) == 1, is_anchored: starts.kind == StartKind::Anchored)
      dfa = new(states, tt, StateID.new(tt.to_index(starts.unanchored)), classes,
        StateID.new(tt.to_index(starts.anchored)), accelerators, nil, quitset, flags)
      dfa.restore_wire_metadata(starts, special, matches.with_state_mapping(match_map.keys, tt), padding)
      dfa.retain_wire_accels(accel_bytes)
      {dfa, reader.offset}
    end

    # Crystal has owned storage, so unchecked decoding uses the safe decoder.
    def self.from_bytes_unchecked(bytes : Bytes) : Tuple(DFA, Int32)
      from_bytes(bytes)
    end

    protected def restore_wire_metadata(@st : StartTable, @special : Special, @ms : MatchStates, @wire_padding : Hash(Int32, UInt32)? = nil) : Nil
    end

    protected def retain_wire_accels(bytes : Bytes) : Nil
      @wire_accels = bytes.dup
    end

    def self.native_wire_endian : Symbol
      IO::ByteFormat::SystemEndian == IO::ByteFormat::LittleEndian ? :little : :big
    end

    def to_bytes_little_endian : Tuple(Bytes, Int32)
      native_wire_bytes(:little)
    end

    def to_bytes_big_endian : Tuple(Bytes, Int32)
      native_wire_bytes(:big)
    end

    # The second element is Rust's alignment padding, not the payload length.
    def to_bytes_native_endian : Tuple(Bytes, Int32)
      native_wire_bytes(:native)
    end

    private def native_wire_bytes(endian : Symbol) : Tuple(Bytes, Int32)
      bytes, padding = Wire.alloc_aligned_buffer(write_to_len, 4)
      write_native_wire(bytes[padding, write_to_len], endian)
      {bytes, padding}
    end

    def write_to_little_endian(dst : Bytes) : Int32
      write_native_wire(dst, :little)
    end

    def write_to_big_endian(dst : Bytes) : Int32
      write_native_wire(dst, :big)
    end

    def write_to_native_endian(dst : Bytes) : Int32
      write_native_wire(dst, :native)
    end

    def write_to_len : Int32
      table = @tt || raise "missing dense transition table"
      48 + 8 + 256 + table.table.size * 4 + @st.write_to_len + @ms.write_to_len + 32 + 4 + (@wire_accels.try(&.size) || wire_accelerators.size * 8) + 32
    end

    private def wire_accelerators : Array(Bytes)
      table = @tt || raise "missing dense transition table"
      return [] of Bytes unless @special.accels?
      first = table.to_index(@special.min_accel)
      last = table.to_index(@special.max_accel)
      @accelerators[first..last]
    end

    private def write_native_wire(dst : Bytes, endian : Symbol) : Int32
      raise SerializeError.buffer_too_small("dense DFA") if dst.size < write_to_len
      table = @tt || raise "missing dense transition table"
      offset = Wire.write_label(WIRE_LABEL, dst)
      offset += Wire.write_endianness_check(dst[offset..], endian)
      offset += Wire.write_version(WIRE_VERSION, dst[offset..], endian)
      offset += Wire.write_u32(0_u32, dst[offset..], endian)
      bits = (@flags.has_empty ? 1_u32 : 0_u32) | (@flags.is_utf8 ? 2_u32 : 0_u32) | (@flags.is_always_start_anchored ? 4_u32 : 0_u32)
      offset += Wire.write_u32(bits, dst[offset..], endian)
      offset += Wire.write_u32(table.len.to_u32, dst[offset..], endian)
      offset += Wire.write_u32(table.stride2.to_u32, dst[offset..], endian)
      offset += @byte_classifier.write_to(dst[offset..])
      table.table.each_with_index do |id, index|
        value = @wire_padding.try(&.[index]?) || id.as_u32
        offset += Wire.write_u32(value, dst[offset..], endian)
      end
      actual_endian = endian == :native ? self.class.native_wire_endian : endian
      offset += @st.write_to(dst[offset..], actual_endian)
      offset += @ms.write_to(dst[offset..], actual_endian)
      special = @special
      {special.max, special.quit_id, special.min_match, special.max_match, special.min_accel, special.max_accel, special.min_start, special.max_start}.each do |id|
        offset += Wire.write_state_id(id, dst[offset..], endian)
      end
      if raw = @wire_accels
        offset += Wire.write_u32((raw.size // 8).to_u32, dst[offset..], endian)
        dst[offset, raw.size].copy_from(raw)
        offset += raw.size
      else
        accels = wire_accelerators
        offset += Wire.write_u32(accels.size.to_u32, dst[offset..], endian)
        accels.each do |needles|
          dst[offset, 8].fill(0_u8)
          dst[offset] = needles.size.to_u8
          dst[offset + 1, needles.size].copy_from(needles)
          offset += 8
        end
      end
      # Rust serializes ByteSet as two endian-aware u128 bitsets.
      quit_bytes = @quitset.to_bytes
      2.times do |index|
        word = IO::ByteFormat::LittleEndian.decode(UInt128, quit_bytes[index * 16, 16])
        offset += Wire.write_u128(word, dst[offset..], endian)
      end
      offset
    end
  end
end
