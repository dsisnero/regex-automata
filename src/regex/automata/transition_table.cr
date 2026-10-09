require "./byte_classes"
require "./types"

module Regex::Automata
  # Flat transition table for DFA with premultiplied state IDs
  #
  # This implements the same optimization as Rust's regex-automata:
  # - Transitions stored in flat array (row-major order)
  # - State IDs are premultiplied by stride (power of 2 ≥ alphabet size)
  # - Fast transition lookup: offset = state_id + byte_class
  class TransitionTable
    getter table : Array(StateID)
    getter classes : ByteClasses
    getter stride2 : Int32 # log2(stride), where stride = 1 << stride2

    # Create a new empty transition table
    def initialize(@classes : ByteClasses, @stride2 : Int32 = 0)
      @table = [] of StateID
    end

    # Create a transition table with given capacity (number of states)
    def initialize(@classes : ByteClasses, @stride2 : Int32, capacity : Int32)
      stride = 1 << @stride2
      @table = Array.new(capacity * stride, Regex::Automata::DFA::DEAD_STATE_ID)
    end

    # Get the stride (number of entries per state)
    def stride : Int32
      1 << @stride2
    end

    # Get the alphabet length (number of byte classes including EOI)
    # This returns the total number of entries per state in the table
    def alphabet_len : Int32
      @classes.alphabet_len
    end

    # Get number of states in the table
    def len : Int32
      @table.size // stride
    end

    # Convert state index to premultiplied state ID
    def to_state_id(index : Int32) : StateID
      # Premultiply by stride: state_id = index << stride2
      StateID.new(index << @stride2)
    end

    # Convert premultiplied state ID to state index
    def to_index(state_id : StateID) : Int32
      # Divide by stride: index = state_id >> stride2
      state_id.to_i >> @stride2
    end

    # Check if state ID is valid (within table bounds)
    def is_valid(state_id : StateID) : Bool
      raw = state_id.to_i
      raw >= 0 && raw < @table.size && raw % stride == 0
    end

    def memory_usage : Int32
      (@table.size * sizeof(StateID)).to_i32
    end

    def validate : DeserializeError?
      @table.each do |state_id|
        return DeserializeError.generic("found invalid state ID in transition table") unless is_valid(state_id)
      end
      nil
    end

    # Get next state for given state ID and byte
    def next_state(state_id : StateID, byte : UInt8) : StateID
      byte_class = @classes[byte]
      offset = state_id.to_i + byte_class
      @table[offset]
    end

    # Get next state for given state ID and byte class
    def next_state_by_class(state_id : StateID, byte_class : Int32) : StateID
      offset = state_id.to_i + byte_class
      @table[offset]
    end

    # Get next state for EOI (end of input) transition
    # Note: EOI is handled as a special case, not through byte classes
    def next_eoi_state(state_id : StateID) : StateID
      eoi_class = @classes.alphabet_len - 1
      offset = state_id.to_i + eoi_class
      @table[offset]
    end

    # Set transition for given state ID and byte
    def set_transition(state_id : StateID, byte : UInt8, target : StateID)
      byte_class = @classes[byte]
      offset = state_id.to_i + byte_class
      @table[offset] = target
    end

    # Set transition for given state ID and byte class
    def set_transition_by_class(state_id : StateID, byte_class : Int32, target : StateID)
      offset = state_id.to_i + byte_class
      @table[offset] = target
    end

    # Set EOI transition for given state ID
    # EOI is treated as one past the last regular byte class
    def set_eoi_transition(state_id : StateID, target : StateID)
      eoi_class = @classes.alphabet_len - 1
      offset = state_id.to_i + eoi_class
      @table[offset] = target
    end

    # Add a new state and return its premultiplied state ID
    def add_state : StateID
      # Add stride entries for the new state
      stride = self.stride
      new_len = @table.size + stride
      @table.concat(Array.new(stride, Regex::Automata::DFA::DEAD_STATE_ID))

      # Return premultiplied state ID
      to_state_id(len - 1)
    end

    # Get slice of transitions for a given state
    def state_slice(state_id : StateID) : Slice(StateID)
      idx = to_index(state_id)
      start = idx * stride
      Slice.new(@table.to_unsafe + start, stride)
    end

    # Copy transitions from one state to another
    def copy_state(src_id : StateID, dst_id : StateID)
      src_slice = state_slice(src_id)
      dst_slice = state_slice(dst_id)

      # Copy only the used portion (alphabet_len entries)
      alphabet_len = self.alphabet_len
      (0...alphabet_len).each do |i|
        dst_slice[i] = src_slice[i]
      end
    end

    # Swap two states
    def swap(id1 : StateID, id2 : StateID)
      idx1 = to_index(id1)
      idx2 = to_index(id2)

      stride = self.stride
      start1 = idx1 * stride
      start2 = idx2 * stride

      # Only swap the used portion (alphabet_len entries)
      alphabet_len = self.alphabet_len
      (0...alphabet_len).each do |i|
        @table[start1 + i], @table[start2 + i] = @table[start2 + i], @table[start1 + i]
      end
    end

    # Remap all transitions in a state using given mapping function
    def remap(state_id : StateID, &block : StateID -> StateID)
      idx = to_index(state_id)
      start = idx * stride

      alphabet_len = self.alphabet_len
      (0...alphabet_len).each do |i|
        offset = start + i
        @table[offset] = block.call(@table[offset])
      end
    end

    # Get the state ID for the next state (state index + 1)
    def next_state_id(state_id : StateID) : StateID
      idx = to_index(state_id)
      to_state_id(idx + 1)
    end

    # Get the state ID for the previous state (state index - 1)
    def prev_state_id(state_id : StateID) : StateID
      idx = to_index(state_id)
      to_state_id(idx - 1)
    end

    # Serialize to bytes
    def to_bytes(endian : Symbol = :little) : Bytes
      # Calculate total size
      # 4 bytes: state length (u32)
      # 4 bytes: stride2 (u32)
      # byte classes serialization
      # transitions: len * stride * 4 bytes (each StateID is u32)

      state_len = len
      stride = self.stride

      # Serialize byte classes first to know its size
      classes_bytes = @classes.to_bytes(endian)

      total_size = 8 + classes_bytes.size + (state_len * stride * 4)
      buffer = Bytes.new(total_size)

      # Use pointer arithmetic for faster copying
      buffer_ptr = buffer.to_unsafe
      offset = 0

      # Write state length
      if endian == :little
        buffer_ptr[offset] = (state_len & 0xFF).to_u8
        buffer_ptr[offset + 1] = ((state_len >> 8) & 0xFF).to_u8
        buffer_ptr[offset + 2] = ((state_len >> 16) & 0xFF).to_u8
        buffer_ptr[offset + 3] = ((state_len >> 24) & 0xFF).to_u8
      else
        buffer_ptr[offset] = ((state_len >> 24) & 0xFF).to_u8
        buffer_ptr[offset + 1] = ((state_len >> 16) & 0xFF).to_u8
        buffer_ptr[offset + 2] = ((state_len >> 8) & 0xFF).to_u8
        buffer_ptr[offset + 3] = (state_len & 0xFF).to_u8
      end
      offset += 4

      # Write stride2
      if endian == :little
        buffer_ptr[offset] = (@stride2 & 0xFF).to_u8
        buffer_ptr[offset + 1] = ((@stride2 >> 8) & 0xFF).to_u8
        buffer_ptr[offset + 2] = ((@stride2 >> 16) & 0xFF).to_u8
        buffer_ptr[offset + 3] = ((@stride2 >> 24) & 0xFF).to_u8
      else
        buffer_ptr[offset] = ((@stride2 >> 24) & 0xFF).to_u8
        buffer_ptr[offset + 1] = ((@stride2 >> 16) & 0xFF).to_u8
        buffer_ptr[offset + 2] = ((@stride2 >> 8) & 0xFF).to_u8
        buffer_ptr[offset + 3] = (@stride2 & 0xFF).to_u8
      end
      offset += 4

      # Write byte classes using copy_to
      classes_bytes.copy_to(buffer[offset, classes_bytes.size])
      offset += classes_bytes.size

      # State IDs are serialized explicitly instead of reinterpreting an
      # Array's backing storage. Crystal owns decoded storage, so this keeps
      # both endian forms valid for arbitrary Bytes slices.
      @table.each_with_index do |state_id, i|
        write_state_id(state_id.to_i, buffer, offset + i * sizeof(Int32), endian)
      end

      buffer
    end

    # Deserialize from bytes
    def self.from_bytes(bytes : Bytes, endian : Symbol = :little) : TransitionTable
      raise DeserializeError.buffer_too_small("transition table header") if bytes.size < 8
      offset = 0

      # Read state length
      state_len = if endian == :little
                    bytes[offset].to_i32 |
                      (bytes[offset + 1].to_i32 << 8) |
                      (bytes[offset + 2].to_i32 << 16) |
                      (bytes[offset + 3].to_i32 << 24)
                  else
                    (bytes[offset].to_i32 << 24) |
                      (bytes[offset + 1].to_i32 << 16) |
                      (bytes[offset + 2].to_i32 << 8) |
                      bytes[offset + 3].to_i32
                  end
      offset += 4

      # Read stride2
      stride2 = if endian == :little
                  bytes[offset].to_i32 |
                    (bytes[offset + 1].to_i32 << 8) |
                    (bytes[offset + 2].to_i32 << 16) |
                    (bytes[offset + 3].to_i32 << 24)
                else
                  (bytes[offset].to_i32 << 24) |
                    (bytes[offset + 1].to_i32 << 16) |
                    (bytes[offset + 2].to_i32 << 8) |
                    bytes[offset + 3].to_i32
                end
      offset += 4

      raise DeserializeError.generic("dense DFA has invalid state length") if state_len < 0
      raise DeserializeError.generic("dense DFA has invalid stride2 (too small)") if stride2 < 1
      raise DeserializeError.generic("dense DFA has invalid stride2 (too big)") if stride2 > 9
      raise DeserializeError.buffer_too_small("dense DFA byte classes") if bytes.size < offset + 256

      # Read byte classes
      classes, classes_size = ByteClasses.from_bytes(bytes[offset..], endian)
      offset += classes_size

      # Create transition table
      stride = 1 << stride2
      raise DeserializeError.generic("alphabet size cannot be bigger than transition table stride") if classes.alphabet_len > stride
      table = TransitionTable.new(classes, stride2, state_len)

      # Read transitions in bulk
      transitions_size = state_len.to_i64 * stride * sizeof(Int32)
      raise DeserializeError.generic("dense table transition length is too large") if transitions_size > Int32::MAX
      raise DeserializeError.buffer_too_small("transition table") if bytes.size < offset + transitions_size
      transitions_bytes = bytes[offset, transitions_size]

      (0...state_len * stride).each do |i|
        byte_offset = i * sizeof(Int32)
        table.table[i] = StateID.new(read_state_id(transitions_bytes, byte_offset, endian))
      end

      if error = table.validate
        raise error
      end
      table
    end

    private def write_state_id(value : Int32, buffer : Bytes, offset : Int32, endian : Symbol) : Nil
      if endian == :little
        buffer[offset] = (value & 0xFF).to_u8
        buffer[offset + 1] = ((value >> 8) & 0xFF).to_u8
        buffer[offset + 2] = ((value >> 16) & 0xFF).to_u8
        buffer[offset + 3] = ((value >> 24) & 0xFF).to_u8
      else
        buffer[offset] = ((value >> 24) & 0xFF).to_u8
        buffer[offset + 1] = ((value >> 16) & 0xFF).to_u8
        buffer[offset + 2] = ((value >> 8) & 0xFF).to_u8
        buffer[offset + 3] = (value & 0xFF).to_u8
      end
    end

    private def self.read_state_id(bytes : Bytes, offset : Int32, endian : Symbol) : Int32
      if endian == :little
        bytes[offset].to_i32 |
          (bytes[offset + 1].to_i32 << 8) |
          (bytes[offset + 2].to_i32 << 16) |
          (bytes[offset + 3].to_i32 << 24)
      else
        (bytes[offset].to_i32 << 24) |
          (bytes[offset + 1].to_i32 << 16) |
          (bytes[offset + 2].to_i32 << 8) |
          bytes[offset + 3].to_i32
      end
    end
  end
end
