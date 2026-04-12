module Regex::Automata
  MAX_UTF8_BYTES = 4

  # UTF-8 byte range (inclusive)
  struct Utf8Range
    getter start : UInt8
    getter end : UInt8

    def initialize(@start : UInt8, @end : UInt8)
    end

    def matches(b : UInt8) : Bool
      @start <= b && b <= @end
    end

    def to_s(io)
      if @start == @end
        io << "[%02X]" % @start
      else
        io << "[%02X-%02X]" % [@start, @end]
      end
    end

    def inspect(io)
      to_s(io)
    end
  end

  # A sequence of UTF-8 byte ranges that must be matched in order
  class Utf8Sequence
    @ranges : Array(Utf8Range)

    def initialize(@ranges : Array(Utf8Range))
    end

    def self.one(range : Utf8Range) : Utf8Sequence
      new([range])
    end

    def self.two(r1, r2) : Utf8Sequence
      new([r1, r2])
    end

    def self.three(r1, r2, r3) : Utf8Sequence
      new([r1, r2, r3])
    end

    def self.four(r1, r2, r3, r4) : Utf8Sequence
      new([r1, r2, r3, r4])
    end

    # Create from encoded start and end bytes (same length)
    def self.from_encoded_range(start : Bytes, end_bytes : Bytes) : Utf8Sequence
      raise "length mismatch" unless start.size == end_bytes.size
      ranges = start.size.times.map do |i|
        Utf8Range.new(start[i], end_bytes[i])
      end.to_a
      new(ranges)
    end

    def ranges : Array(Utf8Range)
      @ranges
    end

    def size : Int32
      @ranges.size
    end

    # Check if this sequence matches the given bytes (exact length)
    def matches(bytes : Bytes) : Bool
      return false if bytes.size != @ranges.size
      @ranges.each_with_index do |range, i|
        return false unless range.matches(bytes[i])
      end
      true
    end

    def to_s(io)
      @ranges.each { |r| io << r }
      io
    end

    def inspect(io)
      to_s(io)
    end
  end

  private class ScalarRange
    getter start : UInt32
    getter end : UInt32

    def initialize(@start : UInt32, @end : UInt32)
    end

    # Split if overlapping with surrogate codepoints (0xD800-0xDFFF)
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
      if ascii?
        Utf8Range.new(@start.to_u8, @end.to_u8)
      end
    end

    # Encode start and end to UTF-8 bytes, return number of bytes written
    def encode(start_buf : Bytes, end_buf : Bytes) : Int32
      cs = @start.chr
      ce = @end.chr

      cs_str = cs.to_s
      ce_str = ce.to_s

      cs_str.bytes.each_with_index { |b, i| start_buf[i] = b }
      ce_str.bytes.each_with_index { |b, i| end_buf[i] = b }

      cs_str.bytesize
    end
  end

  # Iterator over UTF-8 byte sequences for a given Unicode scalar range
  class Utf8Sequences
    @range_stack : Array(ScalarRange)

    def initialize(start : Char, end_char : Char)
      @range_stack = [ScalarRange.new(start.ord.to_u32, end_char.ord.to_u32)]
    end

    def next : Utf8Sequence?
      while r = @range_stack.pop?
        # Process with inner loop
        loop do
          # Split surrogates
          if split = r.split
            r1, r2 = split
            @range_stack << ScalarRange.new(r2.start, r2.end)
            r = ScalarRange.new(r1.start, r1.end)
            next
          end

          break unless r.valid?

          # Split at UTF-8 length boundaries
          split_at_boundary = false
          (1...MAX_UTF8_BYTES).each do |i|
            max = max_scalar_value(i)
            if r.start <= max && max < r.end
              @range_stack << ScalarRange.new(max + 1, r.end)
              r = ScalarRange.new(r.start, max)
              split_at_boundary = true
              break
            end
          end
          next if split_at_boundary

          # ASCII range
          if ascii_range = r.as_ascii_range
            return Utf8Sequence.one(ascii_range)
          end

          # Split based on alignment
          (1...MAX_UTF8_BYTES).each do |i|
            m = (1_u32 << (6 * i)) - 1
            if (r.start & ~m) != (r.end & ~m)
              if (r.start & m) != 0
                @range_stack << ScalarRange.new((r.start | m) + 1, r.end)
                r = ScalarRange.new(r.start, r.start | m)
                next
              end
              if (r.end & m) != m
                @range_stack << ScalarRange.new(r.end & ~m, r.end)
                r = ScalarRange.new(r.start, (r.end & ~m) - 1)
                next
              end
            end
          end

          # Encode the range
          start_buf = uninitialized UInt8[MAX_UTF8_BYTES]
          end_buf = uninitialized UInt8[MAX_UTF8_BYTES]
          n = r.encode(start_buf.to_slice, end_buf.to_slice)
          return Utf8Sequence.from_encoded_range(
            start_buf.to_slice[0, n],
            end_buf.to_slice[0, n]
          )
        end
      end
      nil
    end

    def each : Iterator(Utf8Sequence)
      Iterator.of do
        next_value = self.next
        next_value ? next_value : stop
      end
    end

    private def max_scalar_value(nbytes : Int32) : UInt32
      case nbytes
      when 1 then 0x007F_u32
      when 2 then 0x07FF_u32
      when 3 then 0xFFFF_u32
      when 4 then 0x0010_FFFF_u32
      else        raise "invalid UTF-8 byte sequence size"
      end
    end
  end
end
