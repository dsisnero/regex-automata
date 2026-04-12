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
  end
end
