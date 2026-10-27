module Regex::Automata
  module Wire
    struct AlignAs(B, T)
      @align : StaticArray(T, 0)
      getter bytes : B

      def initialize(@bytes : B)
        @align = StaticArray(T, 0).new(uninitialized)
      end
    end

    def self.skip_initial_padding(slice : Bytes) : Int32
      nread = 0
      while nread < 7 && nread < slice.size && slice[nread] == 0
        nread += 1
      end
      nread
    end

    def self.check_alignment(slice : Bytes, alignment : Int32) : Nil
      raise ArgumentError.new("alignment must be positive") if alignment <= 0
      address = slice.to_unsafe.address.to_u64
      raise DeserializeError.alignment_mismatch(alignment, address) unless address % alignment == 0
    end

    def self.alloc_aligned_buffer(size : Int32, alignment : Int32) : Tuple(Bytes, Int32)
      raise ArgumentError.new("alignment must be a power of two at most 8") if alignment < 1 || alignment > 8 || (alignment & (alignment - 1)) != 0
      buffer = Bytes.new(size + alignment - 1, 0_u8)
      address = buffer.to_unsafe.address.to_u64
      padding = ((alignment - (address % alignment)) % alignment).to_i32
      {buffer[0, size + padding], padding}
    end

    def self.check_slice_len(slice : Slice, at_least_len : Int, what : String) : Nil
      raise DeserializeError.buffer_too_small(what) if slice.size < at_least_len
    end

    def self.read_u16(slice : Bytes) : UInt16
      IO::ByteFormat::SystemEndian.decode(UInt16, slice[0, 2])
    end

    def self.read_u32(slice : Bytes) : UInt32
      IO::ByteFormat::SystemEndian.decode(UInt32, slice[0, 4])
    end

    def self.read_u128(slice : Bytes) : UInt128
      IO::ByteFormat::SystemEndian.decode(UInt128, slice[0, 16])
    end

    def self.try_read_u16(slice : Bytes, what : String) : Tuple(UInt16, Int32)
      check_slice_len(slice, 2, what)
      {read_u16(slice), 2}
    end

    def self.try_read_u32(slice : Bytes, what : String) : Tuple(UInt32, Int32)
      check_slice_len(slice, 4, what)
      {read_u32(slice), 4}
    end

    def self.try_read_u128(slice : Bytes, what : String) : Tuple(UInt128, Int32)
      check_slice_len(slice, 16, what)
      {read_u128(slice), 16}
    end

    def self.try_read_u16_as_usize(slice : Bytes, what : String) : Tuple(UInt64, Int32)
      value, read = try_read_u16(slice, what)
      {value.to_u64, read}
    end

    def self.try_read_u32_as_usize(slice : Bytes, what : String) : Tuple(UInt64, Int32)
      value, read = try_read_u32(slice, what)
      {value.to_u64, read}
    end

    def self.read_endianness_check(slice : Bytes) : Int32
      value, read = try_read_u32(slice, "endianness check")
      raise DeserializeError.endian_mismatch(0xFEFF_u32, value) unless value == 0xFEFF_u32
      read
    end

    def self.read_version(slice : Bytes, expected_version : UInt32) : Int32
      value, read = try_read_u32(slice, "version")
      raise DeserializeError.version_mismatch(expected_version, value) unless value == expected_version
      read
    end

    def self.write_endianness_check(dst : Bytes, endianness : Symbol = :native) : Int32
      check_write_len(dst, 4, "endianness check")
      write_u32(0xFEFF_u32, dst, endianness)
    end

    def self.write_endianness_check_len : Int32
      4
    end

    def self.write_version(version : UInt32, dst : Bytes, endianness : Symbol = :native) : Int32
      check_write_len(dst, 4, "version number")
      write_u32(version, dst, endianness)
    end

    def self.write_version_len : Int32
      4
    end

    def self.write_pattern_id(pid : PatternID, dst : Bytes, endianness : Symbol = :native) : Int32
      write_u32(pid.as_u32, dst, endianness)
    end

    def self.write_state_id(sid : StateID, dst : Bytes, endianness : Symbol = :native) : Int32
      write_u32(sid.as_u32, dst, endianness)
    end

    def self.write_u16(value : UInt16, dst : Bytes, endianness : Symbol = :native) : Int32
      case endianness
      when :little then IO::ByteFormat::LittleEndian.encode(value, dst)
      when :big    then IO::ByteFormat::BigEndian.encode(value, dst)
      when :native then IO::ByteFormat::SystemEndian.encode(value, dst)
      else              raise ArgumentError.new("unknown endianness: #{endianness}")
      end
      2
    end

    def self.write_u32(value : UInt32, dst : Bytes, endianness : Symbol = :native) : Int32
      case endianness
      when :little then IO::ByteFormat::LittleEndian.encode(value, dst)
      when :big    then IO::ByteFormat::BigEndian.encode(value, dst)
      when :native then IO::ByteFormat::SystemEndian.encode(value, dst)
      else              raise ArgumentError.new("unknown endianness: #{endianness}")
      end
      4
    end

    def self.write_u128(value : UInt128, dst : Bytes, endianness : Symbol = :native) : Int32
      case endianness
      when :little then IO::ByteFormat::LittleEndian.encode(value, dst)
      when :big    then IO::ByteFormat::BigEndian.encode(value, dst)
      when :native then IO::ByteFormat::SystemEndian.encode(value, dst)
      else              raise ArgumentError.new("unknown endianness: #{endianness}")
      end
      16
    end

    private def self.check_write_len(dst : Bytes, length : Int32, what : String) : Nil
      raise SerializeError.buffer_too_small(what) if dst.size < length
    end

    def self.try_read_state_id(slice : Bytes, what : String) : Tuple(StateID, Int32)
      check_slice_len(slice, StateID::SIZE, what)
      read_state_id(slice, what)
    end

    def self.read_state_id(slice : Bytes, what : String) : Tuple(StateID, Int32)
      value = StateID.from_ne_bytes(slice[0, StateID::SIZE])
      raise DeserializeError.state_id_error(value, what) if value.is_a?(StateIDError)
      {value, StateID::SIZE}
    end

    def self.read_pattern_id(slice : Bytes, what : String) : Tuple(PatternID, Int32)
      value = PatternID.from_ne_bytes(slice[0, PatternID::SIZE])
      raise DeserializeError.pattern_id_error(value, what) if value.is_a?(PatternIDError)
      {value, PatternID::SIZE}
    end

    def self.read_state_id_unchecked(slice : Bytes) : Tuple(StateID, Int32)
      {StateID.from_ne_bytes_unchecked(slice[0, StateID::SIZE]), StateID::SIZE}
    end

    def self.read_pattern_id_unchecked(slice : Bytes) : Tuple(PatternID, Int32)
      {PatternID.from_ne_bytes_unchecked(slice[0, PatternID::SIZE]), PatternID::SIZE}
    end

    def self.add(a : UInt64, b : UInt64, what : String) : UInt64
      raise DeserializeError.arithmetic_overflow(what) if a > UInt64::MAX - b
      a + b
    end

    def self.mul(a : UInt64, b : UInt64, what : String) : UInt64
      raise DeserializeError.arithmetic_overflow(what) if b != 0 && a > UInt64::MAX // b
      a * b
    end

    def self.shl(a : UInt64, b : UInt64, what : String) : UInt64
      raise DeserializeError.arithmetic_overflow(what) if b >= 64
      a << b.to_i
    end

    def self.read_label(slice : Bytes, expected_label : String) : Int32
      search_len = Math.min(slice.size, 256)
      first_nul = slice[0, search_len].index(0_u8)
      raise DeserializeError.generic("could not find NUL terminated label at start of serialized object") if first_nul.nil?

      nul_index = first_nul.not_nil!
      # Preserve wire.rs::read_label, including its first_nul-based padding.
      total_len = nul_index + padding_len(nul_index)
      if slice.size < total_len
        raise DeserializeError.generic("could not find properly sized label at start of serialized object")
      end
      if slice[0, nul_index] != expected_label.to_slice
        raise DeserializeError.label_mismatch(expected_label)
      end
      total_len.to_i32
    end

    def self.write_label(label : String, dst : Bytes) : Int32
      nwrite = write_label_len(label)
      raise SerializeError.buffer_too_small("label") if dst.size < nwrite

      dst[0, label.bytesize].copy_from(label.to_slice)
      (label.bytesize...nwrite).each do |i|
        dst[i] = 0_u8
      end
      nwrite.to_i32
    end

    def self.write_label_len(label : String) : Int32
      raise ArgumentError.new("label must not be longer than 255 bytes") if label.bytesize > 255
      raise ArgumentError.new("label must not contain NUL bytes") if label.to_slice.includes?(0_u8)

      label_len = label.bytesize + 1
      (label_len + padding_len(label_len)).to_i32
    end

    def self.padding_len(non_padding_len : Int) : Int32
      ((4 - (non_padding_len & 0b11)) & 0b11).to_i32
    end
  end

  class SerializeError
    def self.buffer_too_small(what : String) : self
      new("destination buffer is too small to write #{what}")
    end
  end

  class DeserializeError
    def self.buffer_too_small(what : String) : self
      new("buffer is too small to read #{what}")
    end

    def self.generic(message : String) : self
      new(message)
    end

    def self.invalid_usize(what : String) : self
      new("#{what} is too big to fit in a usize")
    end

    def self.version_mismatch(expected : UInt32, found : UInt32) : self
      new("unsupported version: expected version #{expected} but found version #{found}")
    end

    def self.endian_mismatch(expected : UInt32, found : UInt32) : self
      new("endianness mismatch: expected 0x#{expected.to_s(16, upcase: true)} but got 0x#{found.to_s(16, upcase: true)}. (Are you trying to load an object serialized with a different endianness?)")
    end

    def self.alignment_mismatch(alignment : Int32, address : UInt64) : self
      new("alignment mismatch: slice starts at address 0x#{address.to_s(16, upcase: true)}, which is not aligned to a #{alignment} byte boundary")
    end

    def self.label_mismatch(expected_label : String) : self
      new("label mismatch: start of serialized object should contain a NUL terminated #{expected_label.inspect} label, but a different label was found")
    end

    def self.arithmetic_overflow(what : String) : self
      new("arithmetic overflow for #{what}")
    end

    def self.pattern_id_error(error : PatternIDError, what : String) : self
      new("failed to read pattern ID for #{what}: #{error}")
    end

    def self.state_id_error(error : StateIDError, what : String) : self
      new("failed to read state ID for #{what}: #{error}")
    end
  end
end
