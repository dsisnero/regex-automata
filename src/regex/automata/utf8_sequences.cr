module Regex::Automata
  MAX_UTF8_BYTES = 4

  module Utf8
    WORD_BYTE_TABLE = begin
      table = StaticArray(Bool, 256).new(false)
      table['_'.ord.to_u8] = true

      ('0'.ord..'9'.ord).each { |ord| table[ord.to_u8] = true }
      ('A'.ord..'Z'.ord).each { |ord| table[ord.to_u8] = true }
      ('a'.ord..'z'.ord).each { |ord| table[ord.to_u8] = true }
      table
    end

    def self.is_word_byte(byte : UInt8) : Bool
      WORD_BYTE_TABLE[byte]
    end

    def self.decode(bytes : Bytes) : Char | UInt8 | Nil
      return nil if bytes.empty?

      len = codepoint_len(bytes[0])
      return bytes[0] if len.nil? || len > bytes.size
      return bytes[0].chr if len == 1

      string = String.new(bytes[0, len])
      return bytes[0] unless string.valid_encoding?

      string.each_char.first
    end

    def self.decode_last(bytes : Bytes) : Char | UInt8 | Nil
      return nil if bytes.empty?

      start = bytes.size - 1
      limit = bytes.size > 4 ? bytes.size - 4 : 0
      while start > limit && !leading_or_invalid_byte?(bytes[start])
        start -= 1
      end

      result = decode(bytes[start, bytes.size - start])
      case result
      when Char
        result
      when UInt8
        bytes[bytes.size - 1]
      else
        nil
      end
    end

    def self.is_boundary(bytes : Bytes, index : Int32) : Bool
      return false if index < 0
      return true if index == bytes.size
      return false if index > bytes.size

      byte = bytes[index]
      byte <= 0b0111_1111_u8 || byte >= 0b1100_0000_u8
    end

    private def self.codepoint_len(byte : UInt8) : Int32?
      case byte
      when 0b0000_0000_u8..0b0111_1111_u8 then 1
      when 0b1000_0000_u8..0b1011_1111_u8 then nil
      when 0b1100_0000_u8..0b1101_1111_u8 then 2
      when 0b1110_0000_u8..0b1110_1111_u8 then 3
      when 0b1111_0000_u8..0b1111_0111_u8 then 4
      else
        nil
      end
    end

    private def self.leading_or_invalid_byte?(byte : UInt8) : Bool
      (byte & 0b1100_0000_u8) != 0b1000_0000_u8
    end
  end

  struct Utf8Range
    getter start : UInt8
    getter end : UInt8

    def initialize(@start : UInt8, @end : UInt8)
    end

    def matches(byte : UInt8) : Bool
      @start <= byte && byte <= @end
    end

    def to_s(io : IO) : Nil
      if @start == @end
        io << "[%02X]" % @start
      else
        io << "[%02X-%02X]" % [@start, @end]
      end
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end

  class Utf8Sequence
    getter ranges : Array(Utf8Range)

    def initialize(@ranges : Array(Utf8Range))
    end

    def self.one(range : Utf8Range) : Utf8Sequence
      new([range])
    end

    def self.two(r1 : Utf8Range, r2 : Utf8Range) : Utf8Sequence
      new([r1, r2])
    end

    def self.three(r1 : Utf8Range, r2 : Utf8Range, r3 : Utf8Range) : Utf8Sequence
      new([r1, r2, r3])
    end

    def self.four(r1 : Utf8Range, r2 : Utf8Range, r3 : Utf8Range, r4 : Utf8Range) : Utf8Sequence
      new([r1, r2, r3, r4])
    end

    def self.from_encoded_range(start : Bytes, finish : Bytes) : Utf8Sequence
      raise "length mismatch" unless start.size == finish.size

      ranges = start.size.times.map do |i|
        Utf8Range.new(start[i], finish[i])
      end.to_a
      new(ranges)
    end

    def size : Int32
      @ranges.size
    end

    def matches(bytes : Bytes) : Bool
      return false if bytes.size != @ranges.size

      @ranges.each_with_index.all? do |range, i|
        range.matches(bytes[i])
      end
    end

    def to_s(io : IO) : Nil
      @ranges.each { |range| io << range }
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end

  private class ScalarRange
    getter start : UInt32
    getter end : UInt32

    def initialize(@start : UInt32, @end : UInt32)
    end

    def split : Tuple(ScalarRange, ScalarRange)?
      if @start < 0xE000_u32 && @end > 0xD7FF_u32
        {
          ScalarRange.new(@start, 0xD7FF_u32),
          ScalarRange.new(0xE000_u32, @end),
        }
      end
    end

    def valid? : Bool
      @start <= @end
    end

    def ascii? : Bool
      valid? && @end <= 0x7F_u32
    end

    def as_ascii_range : Utf8Range?
      Utf8Range.new(@start.to_u8, @end.to_u8) if ascii?
    end

    def encode(start_buf : Bytes, end_buf : Bytes) : Int32
      start_string = @start.chr.to_s
      end_string = @end.chr.to_s

      start_string.bytes.each_with_index { |byte, i| start_buf[i] = byte }
      end_string.bytes.each_with_index { |byte, i| end_buf[i] = byte }
      start_string.bytesize
    end
  end

  class Utf8Sequences
    @range_stack : Array(ScalarRange)

    def initialize(start : Char, finish : Char)
      @range_stack = [ScalarRange.new(start.ord.to_u32, finish.ord.to_u32)]
    end

    def next : Utf8Sequence?
      while range = @range_stack.pop?
        loop do
          if split = range.split
            first, second = split
            @range_stack << second
            range = first
            next
          end

          break unless range.valid?

          split_at_boundary = false
          (1...MAX_UTF8_BYTES).each do |width|
            max = max_scalar_value(width)
            if range.start <= max && max < range.end
              @range_stack << ScalarRange.new(max + 1, range.end)
              range = ScalarRange.new(range.start, max)
              split_at_boundary = true
              break
            end
          end
          next if split_at_boundary

          if ascii_range = range.as_ascii_range
            return Utf8Sequence.one(ascii_range)
          end

          split_for_alignment = false
          (1...MAX_UTF8_BYTES).each do |width|
            mask = (1_u32 << (6 * width)) - 1
            if (range.start & ~mask) != (range.end & ~mask)
              if (range.start & mask) != 0
                @range_stack << ScalarRange.new((range.start | mask) + 1, range.end)
                range = ScalarRange.new(range.start, range.start | mask)
                split_for_alignment = true
                break
              end
              if (range.end & mask) != mask
                @range_stack << ScalarRange.new(range.end & ~mask, range.end)
                range = ScalarRange.new(range.start, (range.end & ~mask) - 1)
                split_for_alignment = true
                break
              end
            end
          end
          next if split_for_alignment

          start_buf = uninitialized UInt8[MAX_UTF8_BYTES]
          end_buf = uninitialized UInt8[MAX_UTF8_BYTES]
          size = range.encode(start_buf.to_slice, end_buf.to_slice)
          return Utf8Sequence.from_encoded_range(start_buf.to_slice[0, size], end_buf.to_slice[0, size])
        end
      end
      nil
    end

    def each : Iterator(Utf8Sequence)
      Iterator.of do
        value = self.next
        value ? value : stop
      end
    end

    private def max_scalar_value(width : Int32) : UInt32
      case width
      when 1 then 0x007F_u32
      when 2 then 0x07FF_u32
      when 3 then 0xFFFF_u32
      when 4 then 0x0010_FFFF_u32
      else
        raise "invalid UTF-8 byte sequence size"
      end
    end
  end
end
