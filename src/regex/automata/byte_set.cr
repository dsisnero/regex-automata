module Regex::Automata
  class ByteSet
    include Enumerable(UInt8)

    @bits : StaticArray(Bool, 256)

    def initialize
      @bits = StaticArray(Bool, 256).new(false)
    end

    def self.empty : ByteSet
      new
    end

    def add(byte : UInt8) : ByteSet
      @bits[byte] = true
      self
    end

    def remove(byte : UInt8) : ByteSet
      @bits[byte] = false
      self
    end

    def contains(byte : UInt8) : Bool
      @bits[byte]
    end

    def includes?(byte : UInt8) : Bool
      contains(byte)
    end

    def contains_range(start : UInt8, finish : UInt8) : Bool
      (start..finish).all? { |byte| contains(byte) }
    end

    def each(& : UInt8 ->) : Nil
      256.times do |byte|
        value = byte.to_u8
        yield value if contains(value)
      end
    end

    def iter : ByteSetIter
      ByteSetIter.new(self)
    end

    def iter_ranges : ByteSetRangeIter
      ByteSetRangeIter.new(self)
    end

    def empty? : Bool
      @bits.all? { |bit| !bit }
    end

    def is_empty : Bool
      empty?
    end

    def to_bytes : Bytes
      bytes = Bytes.new(32, 0_u8)
      256.times do |i|
        next unless @bits[i]

        byte_index = i // 8
        bit_index = i % 8
        bytes[byte_index] |= (1 << bit_index).to_u8
      end
      bytes
    end

    def self.from_bytes(bytes : Bytes) : ByteSet
      raise IndexError.new if bytes.size < 32

      set = ByteSet.new
      256.times do |i|
        byte_index = i // 8
        bit_index = i % 8
        if (bytes[byte_index] & (1 << bit_index).to_u8) != 0
          set.add(i.to_u8)
        end
      end
      set
    end
  end

  class ByteSetIter
    include Iterator(UInt8)

    def initialize(@set : ByteSet, @byte : Int32 = 0)
    end

    def next
      while @byte <= 255
        current = @byte.to_u8
        @byte += 1
        return current if @set.contains(current)
      end
      stop
    end
  end

  class ByteSetRangeIter
    include Iterator(Tuple(UInt8, UInt8))

    def initialize(@set : ByteSet, @byte : Int32 = 0)
    end

    def next
      while @byte <= 255
        start = @byte.to_u8
        @byte += 1
        next unless @set.contains(start)

        finish = start
        while @byte <= 255 && @set.contains(@byte.to_u8)
          finish = @byte.to_u8
          @byte += 1
        end
        return {start, finish}
      end
      stop
    end
  end
end
