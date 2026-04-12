module Regex::Automata
  # Simple set of bytes (0-255)
  class ByteSet
    @bits : StaticArray(Bool, 256)

    def initialize
      @bits = StaticArray(Bool, 256).new(false)
    end

    # Create an empty ByteSet
    def self.empty : ByteSet
      new
    end

    # Add a byte to the set
    def add(byte : UInt8) : ByteSet
      @bits[byte] = true
      self
    end

    # Remove a byte from the set
    def remove(byte : UInt8) : ByteSet
      @bits[byte] = false
      self
    end

    # Check if byte is in set
    def includes?(byte : UInt8) : Bool
      @bits[byte]
    end

    # Check if set is empty
    def empty? : Bool
      256.times do |i|
        return false if @bits[i]
      end
      true
    end

    # Convert to bytes (32 bytes for 256 bits)
    def to_bytes : Bytes
      bytes = Bytes.new(32)
      256.times do |i|
        if @bits[i]
          byte_index = i // 8
          bit_index = i % 8
          bytes[byte_index] |= (1 << bit_index).to_u8
        end
      end
      bytes
    end

    # Create from bytes
    def self.from_bytes(bytes : Bytes) : ByteSet
      set = ByteSet.new
      256.times do |i|
        byte_index = i // 8
        bit_index = i % 8
        if bytes[byte_index] & (1 << bit_index) != 0
          set.add(i.to_u8)
        end
      end
      set
    end
  end
end
