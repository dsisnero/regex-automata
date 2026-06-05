module Regex::Automata
  # This module defines some core types for dealing with accelerated DFA states.
  # Briefly, a DFA state can be "accelerated" if all of its transitions except
  # for a few loop back to itself. This directly implies that the only way out
  # of such a state is if a byte corresponding to one of those non-loopback
  # transitions is found. Such states are often found in simple repetitions in
  # non-Unicode regexes.
  #
  # In practice, we only consider accelerating states that have 3 or fewer
  # non-loop transitions. At a certain point, you get diminishing returns, but
  # also because that's what the memchr crate supports.

  alias AccelTy = UInt32
  ACCEL_TY_SIZE = sizeof(AccelTy)
  ACCEL_LEN     = 4
  ACCEL_CAP     = 8

  # Search for between 1 and 3 needle bytes in the given haystack, starting the
  # search at the given position. If `needles` has a length other than 1-3,
  # then this panics.
  def self.find_fwd(needles : Slice(UInt8), haystack : Slice(UInt8), at : Int32) : Int32?
    bs = needles
    case needles.size
    when 1
      tail = haystack[at..]?
      return nil unless tail
      idx = tail.index(bs[0])
      idx ? at + idx : nil
    when 2
      # Simple linear search for 2 bytes
      (at...haystack.size).each do |i|
        byte = haystack[i]
        return i if byte == bs[0] || byte == bs[1]
      end
      nil
    when 3
      # Simple linear search for 3 bytes
      (at...haystack.size).each do |i|
        byte = haystack[i]
        return i if byte == bs[0] || byte == bs[1] || byte == bs[2]
      end
      nil
    when 0
      raise "cannot find with empty needles"
    else
      raise "invalid needles length: #{needles.size}"
    end
  end

  # Search for between 1 and 3 needle bytes in the given haystack in reverse,
  # starting the search at the given position. If `needles` has a length other
  # than 1-3, then this panics.
  def self.find_rev(needles : Slice(UInt8), haystack : Slice(UInt8), at : Int32) : Int32?
    bs = needles
    case needles.size
    when 1
      head = haystack[0...at]?
      return nil unless head
      head.rindex(bs[0])
    when 2
      # Simple linear reverse search for 2 bytes
      (0...at).reverse_each do |i|
        byte = haystack[i]
        return i if byte == bs[0] || byte == bs[1]
      end
      nil
    when 3
      # Simple linear reverse search for 3 bytes
      (0...at).reverse_each do |i|
        byte = haystack[i]
        return i if byte == bs[0] || byte == bs[1] || byte == bs[2]
      end
      nil
    when 0
      raise "cannot find with empty needles"
    else
      raise "invalid needles length: #{needles.size}"
    end
  end

  # Accel represents a structure for determining how to "accelerate" a DFA
  # state.
  #
  # Namely, it contains zero or more bytes that must be seen in order for the
  # DFA to leave the state it is associated with. In practice, the actual range
  # is 1 to 3 bytes.
  #
  # The purpose of acceleration is to identify states whose vast majority
  # of transitions are just loops back to the same state.
  struct Accel
    @bytes : StaticArray(UInt8, ACCEL_CAP)

    # Returns an empty accel, where no bytes are accelerated.
    def self.empty : Accel
      Accel.new(StaticArray(UInt8, ACCEL_CAP).new(0))
    end

    # Returns a verified accelerator derived from the beginning of the given
    # slice.
    #
    # If the slice is not long enough or contains invalid bytes for an
    # accelerator, then this returns nil.
    def self.from_slice(slice : Slice(UInt8)) : Accel?
      return nil if slice.size < ACCEL_LEN

      bytes = StaticArray(UInt8, ACCEL_CAP).new(0)
      4.times { |i| bytes[i] = slice[i] }

      accel = Accel.new(bytes)
      return nil if accel.len > 3
      accel
    end

    def initialize(@bytes : StaticArray(UInt8, ACCEL_CAP))
    end

    # Attempts to add the given byte to this accelerator. If the accelerator
    # is already full or thinks the byte is a poor accelerator, then this
    # returns false. Otherwise, returns true.
    #
    # If the given byte is already in this accelerator, then it panics.
    def add(byte : UInt8) : Bool
      return false if len >= 3

      # As a special case, we totally reject trying to accelerate a state
      # with an ASCII space. In most cases, it occurs very frequently, and
      # tends to result in worse overall performance.
      return false if byte == ' '.ord.to_u8

      raise "accelerator already contains #{byte}" if contains?(byte)

      @bytes[len + 1] = byte
      @bytes[0] += 1
      true
    end

    # Return the number of bytes in this accelerator.
    def len : Int32
      @bytes[0].to_i
    end

    # Returns true if and only if there are no bytes in this accelerator.
    def empty? : Bool
      len == 0
    end

    # Returns the slice of bytes to accelerate.
    #
    # If this accelerator is empty, then this returns an empty slice.
    def needles : Slice(UInt8)
      Slice.new(@bytes.to_unsafe + 1, len)
    end

    # Returns true if and only if this accelerator will accelerate the given
    # byte.
    def contains?(byte : UInt8) : Bool
      needles.any? { |b| b == byte }
    end

    # Returns the accelerator bytes as an array of AccelTys.
    def as_accel_tys : StaticArray(AccelTy, 2)
      raise "ACCEL_CAP must be 8" unless ACCEL_CAP == 8

      first = IO::ByteFormat::SystemEndian.decode(UInt32, Slice.new(@bytes.to_unsafe, 4))
      second = IO::ByteFormat::SystemEndian.decode(UInt32, Slice.new(@bytes.to_unsafe + 4, 4))
      StaticArray[first, second]
    end

    def to_s(io : IO) : Nil
      io << "Accel("
      needles.each_with_index do |b, i|
        io << ", " if i > 0
        io << "0x"
        b.to_s(io, base: 16, upcase: false)
      end
      io << ")"
    end
  end

  # Represents the accelerators for all accelerated states in a dense DFA.
  struct Accels
    @accels : Slice(AccelTy)

    # Create an empty sequence of accelerators for a DFA.
    def self.empty : Accels
      Accels.new(Slice(AccelTy).new(1, 0_u32))
    end

    # Deserialize a sequence of accelerators from the given raw bytes.
    #
    # This trusts the encoded layout and only checks that enough bytes are
    # present to materialize the declared number of accelerators.
    def self.from_bytes_unchecked(slice : Slice(UInt8)) : Tuple(Accels, Int32)
      raise "accelerators buffer too small" if slice.size < ACCEL_TY_SIZE

      accel_len = IO::ByteFormat::SystemEndian.decode(UInt32, slice[0, ACCEL_TY_SIZE]).to_i
      accel_tys_len = 1 + accel_len * 2
      accel_bytes_len = accel_tys_len * ACCEL_TY_SIZE
      raise "accelerators buffer too small" if slice.size < accel_bytes_len

      accels = Slice(AccelTy).new(accel_tys_len, 0_u32)
      offset = 0
      accel_tys_len.times do |i|
        accels[i] = IO::ByteFormat::SystemEndian.decode(UInt32, slice[offset, ACCEL_TY_SIZE])
        offset += ACCEL_TY_SIZE
      end
      {Accels.new(accels), accel_bytes_len}
    end

    def initialize(@accels : Slice(AccelTy))
    end

    # Add an accelerator to this sequence.
    #
    # This adds to the accelerator to the end of the sequence and therefore
    # should be done in correspondence with its state in the DFA.
    def add(accel : Accel)
      accel_tys = accel.as_accel_tys
      new_accels = Slice(AccelTy).new(@accels.size + 2, 0_u32)
      @accels.copy_to(new_accels.to_unsafe, @accels.size)
      new_accels[@accels.size] = accel_tys[0]
      new_accels[@accels.size + 1] = accel_tys[1]
      @accels = new_accels

      # Update length
      len = self.len
      @accels[0] = (len + 1).to_u32
    end

    # Return the total number of accelerators in this sequence.
    def len : Int32
      @accels[0].to_i
    end

    # Return the bytes to search for corresponding to the accelerator in this
    # sequence at index `i`. If no such accelerator exists, then this panics.
    #
    # The significance of the index is that it should be in correspondence
    # with the index of the corresponding DFA. That is, accelerated DFA
    # states are stored contiguously in the DFA and have an ordering implied
    # by their respective state IDs. The state's index in that sequence
    # corresponds to the index of its corresponding accelerator.
    def needles(i : Int32) : Slice(UInt8)
      raise "invalid accelerator index #{i}" if i >= len

      bytes = self.as_bytes
      offset = ACCEL_TY_SIZE + i * ACCEL_CAP
      len = bytes[offset].to_i
      Slice.new(bytes.to_unsafe + offset + 1, len)
    end

    # Return the accelerator in this sequence at index `i`. If no such
    # accelerator exists, then this returns nil.
    #
    # See the docs for `needles` on the significance of the index.
    def get(i : Int32) : Accel?
      return nil if i >= len

      offset = ACCEL_TY_SIZE + i * ACCEL_CAP
      bytes = Slice(UInt8).new(ACCEL_CAP) { |j| as_bytes[offset + j] }
      Accel.new(StaticArray(UInt8, ACCEL_CAP).new { |i| bytes[i] })
    end

    # Returns the bytes representing the serialization of the accelerators.
    def as_bytes : Slice(UInt8)
      Slice.new(@accels.to_unsafe.as(UInt8*), @accels.size * ACCEL_TY_SIZE)
    end

    # Returns the memory usage, in bytes, of these accelerators.
    #
    # The memory usage is computed based on the number of bytes used to
    # represent all of the accelerators.
    def memory_usage : Int32
      as_bytes.size
    end

    # Returns a borrowed version of the accelerators.
    def as_ref : Accels
      self
    end

    # Returns an owned copy of these accelerators.
    def to_owned : Accels
      Accels.new(@accels.dup)
    end

    # Writes these accelerators to the given byte buffer.
    def write_to(buf : Slice(UInt8)) : Int32
      nwrite = write_to_len
      return 0 if buf.size < nwrite

      bytes = as_bytes
      bytes.copy_to(buf.to_unsafe, nwrite)
      nwrite
    end

    # Returns the total number of bytes written by `write_to`.
    def write_to_len : Int32
      as_bytes.size
    end

    # Validates that every accelerator in this collection can be successfully
    # deserialized as a valid accelerator.
    def validate : Bool
      bytes = as_bytes
      (ACCEL_TY_SIZE...bytes.size).step(ACCEL_CAP) do |offset|
        chunk = bytes[offset, ACCEL_CAP]
        accel = Accel.from_slice(chunk)
        return false if accel.nil?
      end
      true
    end

    def to_s(io : IO) : Nil
      io << "Accels("
      len.times do |i|
        io << ", " if i > 0
        accel = get(i)
        accel.try(&.to_s(io))
      end
      io << ")"
    end
  end
end
