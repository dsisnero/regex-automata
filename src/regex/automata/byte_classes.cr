module Regex::Automata
  # Byte classification for DFA optimization
  # Groups bytes that have identical transitions across all states
  class ByteClasses
    getter classes : Array(Int32)
    getter alphabet_len : Int32

    def initialize(@classes : Array(Int32), @alphabet_len : Int32)
    end

    # Create identity mapping where each byte is its own class
    def self.identity : ByteClasses
      classes = Array.new(256) { |i| i }
      ByteClasses.new(classes, 256)
    end

    # Create byte classes from a DFA by analyzing transitions
    def self.from_dfa(dfa : DFA::DFA) : ByteClasses
      # Start with each byte in its own class
      byte_count = 256
      classes = Array.new(byte_count) { |i| i }
      alphabet_len = byte_count

      # Keep refining until stable
      changed = true
      while changed
        changed = false
        # Group bytes that have same transitions for each state
        new_classes = Array.new(byte_count, 0)
        class_map = {} of Array(Int32) => Int32
        next_class = 0

        byte_count.times do |byte|
          # Build signature: for each state, which next state for this byte
          signature = [] of Int32
          dfa.states.each do |state|
            next_state = state.next[byte]
            signature << next_state.to_i
          end

          # Map signature to class
          if class_map.has_key?(signature)
            new_classes[byte] = class_map[signature]
          else
            new_classes[byte] = next_class
            class_map[signature] = next_class
            next_class += 1
          end
        end

        # Check if classification changed
        if new_classes != classes
          changed = true
          classes = new_classes
          alphabet_len = next_class
        end
      end

      ByteClasses.new(classes, alphabet_len)
    end

    # Create byte classes with quit bytes in separate classes
    def self.with_quitset(quitset : ByteSet) : ByteClasses
      # Start with identity mapping
      classes = Array.new(256) { |i| i }

      # If quit set is empty, return identity
      return ByteClasses.new(classes, 256) if quitset.empty?

      # Group all quit bytes into a single class
      # First, find all quit bytes
      quit_bytes = [] of Int32
      256.times do |i|
        quit_bytes << i if quitset.includes?(i.to_u8)
      end

      # If no quit bytes, return identity
      return ByteClasses.new(classes, 256) if quit_bytes.empty?

      # Put all quit bytes in the same class (class 0)
      quit_class = 0
      quit_bytes.each do |byte|
        classes[byte] = quit_class
      end

      # Reassign other classes starting from 1
      # Each non-quit byte gets its own class initially
      # They will be merged later by from_dfa if they have identical transitions
      next_class = 1
      256.times do |byte|
        if !quit_bytes.includes?(byte)
          classes[byte] = next_class
          next_class += 1
        end
      end

      ByteClasses.new(classes, next_class)
    end

    # Get class for a byte
    def [](byte : UInt8) : Int32
      @classes[byte]
    end

    # Get class for a byte (Int32)
    def [](byte : Int32) : Int32
      @classes[byte]
    end

    # Get a representative byte for a class
    def representative(cls : Int32) : UInt8
      byte = @classes.index(cls)
      raise "Byte class #{cls} has no bytes" unless byte
      byte.to_u8
    end

    # Apply byte classes to a DFA, reducing transition table size
    def apply_to_dfa(dfa : DFA::DFA) : DFA::DFA
      new_states = [] of DFA::State

      dfa.states.each_with_index do |state, i|
        new_state = DFA::State.new(StateID.new(i), @alphabet_len)
        new_state.match.replace(state.match)

        # Build transitions for each class
        @alphabet_len.times do |cls|
          # Find a byte in this class to get transition
          byte = @classes.index(cls)
          if byte
            new_state.set_transition(cls, state.next[byte])
          else
            new_state.set_transition(cls, StateID.new(-1))
          end
        end

        new_states << new_state
      end

      DFA::DFA.new(new_states, dfa.start, self)
    end
  end
end
