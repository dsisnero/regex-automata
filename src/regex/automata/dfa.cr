require "./nfa"
require "./byte_classes"
require "./look"
require "./byte_set"
require "./config"
require "./automaton"
require "./hir_compiler"
require "./transition_table"
require "./match_states"
require "./minimize"
require "./start_table"
require "set"
require "regex-syntax"

module Regex::Automata::DFA
  include Regex::Automata

  # Special state IDs
  DEAD_STATE_ID = StateID.new(0)
  QUIT_STATE_ID = StateID.new(1)

  # Check if a state ID is special (dead or quit)
  def self.special_state?(id : StateID) : Bool
    id == DEAD_STATE_ID || id == QUIT_STATE_ID
  end

  # Check if a state ID is a dead state
  def self.dead_state?(id : StateID) : Bool
    id == DEAD_STATE_ID
  end

  # Check if a state ID is a quit state
  def self.quit_state?(id : StateID) : Bool
    id == QUIT_STATE_ID
  end

  # DFA state with transitions for each byte class
  class State
    getter id : StateID
    property next : Array(StateID)    # indexed by byte class
    property match : Array(PatternID) # empty if not accepting
    getter look_need : LookSet        # look-around assertions present in this state
    getter look_have : LookSet        # look-around assertions satisfied at this state
    getter? is_from_word : Bool       # whether previous byte was a word byte (for word boundaries)
    getter? is_half_crlf : Bool       # whether we're in a half-CRLF state (for CRLF anchors)
    property eoi_next : StateID

    def initialize(@id : StateID, byte_classes : Int32, @look_need : LookSet = LookSet.new, @look_have : LookSet = LookSet.new, @is_from_word : Bool = false, @is_half_crlf : Bool = false)
      @next = Array.new(byte_classes, DEAD_STATE_ID)
      @match = [] of PatternID
      @eoi_next = DEAD_STATE_ID
    end

    # Create a copy of this state with new ID
    def dup(new_id : StateID) : State
      state = State.new(new_id, @next.size, @look_need, @look_have, @is_from_word, @is_half_crlf)
      state.next.replace(@next.dup)
      state.match.replace(@match.dup)
      state.eoi_next = @eoi_next
      state
    end

    def set_transition(byte_class : Int32, target : StateID)
      @next[byte_class] = target
    end

    def add_match(pattern_id : PatternID)
      # Insert in sorted order, maintaining uniqueness
      idx = @match.bsearch_index { |pid| pid >= pattern_id } || @match.size
      if idx == @match.size || @match[idx] != pattern_id
        @match.insert(idx, pattern_id)
      end
    end

    def accepting? : Bool
      !@match.empty?
    end
  end

  # Deterministic Finite Automaton with flat transition table optimization
  class DFA < Regex::Automata::Automaton
    getter states : Array(State) # Original state array (for compatibility)
    getter tt : TransitionTable? # Flat transition table (optional optimization)
    getter st : StartTable
    getter ms : MatchStates
    getter special : Special
    getter start_unanchored : StateID # State ID for unanchored start
    getter start_anchored : StateID   # State ID for anchored start
    getter byte_classifier : ByteClasses
    getter byte_classes : Int32
    # Accelerator bytes for each state (empty slice if not accelerated)
    getter accelerators : Array(Bytes)
    # Prefilter for accelerating searches (optional)
    getter prefilter : Prefilter?
    # Set of bytes that cause the DFA to quit (stop searching)
    getter quitset : ByteSet
    # Various flags describing DFA behavior
    getter flags : DFAFlags

    # Constructor with flat transition table optimization
    def initialize(@states : Array(State), @tt : TransitionTable?, start_unanchored : StateID, byte_classes : ByteClasses | Int32, start_anchored : StateID? = nil, accelerators : Array(Bytes)? = nil, prefilter : Prefilter? = nil, quitset : ByteSet = ByteSet.new, flags : DFAFlags = DFAFlags.new, start_table : StartTable? = nil)
      # Convert start states to premultiplied IDs if we have a transition table
      if @tt
        @start_unanchored = @tt.not_nil!.to_state_id(start_unanchored.to_i)
        @start_anchored = @tt.not_nil!.to_state_id((start_anchored || start_unanchored).to_i)
      else
        @start_unanchored = start_unanchored
        @start_anchored = start_anchored || start_unanchored
      end
      @byte_classifier = case byte_classes
                         when ByteClasses
                           byte_classes
                         when Int32
                           ByteClasses.identity
                         else
                           raise "Unreachable"
                         end
      @byte_classes = @byte_classifier.alphabet_len - 1
      @accelerators = accelerators || Array.new(@states.size) { Bytes.empty }
      @prefilter = prefilter
      @quitset = quitset
      @flags = flags

      if @tt.nil?
        @tt = self.class.build_transition_table(@states, @byte_classifier)
        @start_unanchored = @tt.not_nil!.to_state_id(@start_unanchored.to_i)
        @start_anchored = @tt.not_nil!.to_state_id(@start_anchored.to_i)
      end

      @st = start_table || StartTable.new(
        @flags.is_anchored ? StartKind::Anchored : StartKind::Both,
        @start_unanchored,
        @start_anchored,
        nil,
        nil,
        nil,
        @start_unanchored,
        @start_anchored
      )
      if @tt && start_table
        @st = @st.remap { |id| @tt.not_nil!.to_state_id(id.to_i) }
      end
      @ms = MatchStates.from_states(@states, @tt)
      @special = build_special
    end

    # Create a new DFA from a pattern string using default configuration
    def self.new(pattern : String) : DFA
      Builder.new.build(pattern)
    end

    # Create a new DFA from multiple pattern strings using default configuration
    def self.new_many(patterns : Array(String)) : DFA
      Builder.new.build_many(patterns)
    end

    # Return a default dense DFA builder.
    def self.builder : Builder
      Builder.new
    end

    # Return a default dense DFA configuration.
    def self.config : Config
      Config.new
    end

    # Create a DFA that matches at every position, including empty haystacks.
    def self.always_match : DFA
      Builder.new.build("")
    end

    # Create a DFA that never matches any input.
    def self.never_match : DFA
      nfa = NFA::NFA.new(
        [NFA::Fail.new] of NFA::State,
        StateID.new(0),
        StateID.new(0),
        [] of StateID,
        true,
        false
      )
      Builder.from_nfa(nfa).build
    end

    # Deserialize a DFA from bytes
    # Returns a tuple of (DFA, bytes_read) or raises DeserializeError
    def self.from_bytes(slice : Bytes) : Tuple(DFA, Int32)
      from_bytes_with_endianness(slice, detect_serialized_endianness(slice))
    end

    def self.build_transition_table(states : Array(State), byte_classifier : ByteClasses) : TransitionTable
      stride2 = compute_stride2(byte_classifier)
      tt = TransitionTable.new(byte_classifier, stride2, states.size)
      states.each_with_index do |state, idx|
        state_id = tt.to_state_id(idx)

        state.next.each_with_index do |next_id, byte_class|
          tt.set_transition_by_class(state_id, byte_class, tt.to_state_id(next_id.to_i))
        end

        tt.set_eoi_transition(state_id, tt.to_state_id(state.eoi_next.to_i))
      end
      tt
    end

    def self.compute_stride2(byte_classifier : ByteClasses) : Int32
      alphabet_len = byte_classifier.alphabet_len
      stride2 = 0
      stride = 1
      while stride < alphabet_len
        stride <<= 1
        stride2 += 1
      end
      stride2
    end

    private def self.from_bytes_with_endianness(slice : Bytes, endianness : Symbol) : Tuple(DFA, Int32)
      offset = 0

      ensure_bytes_available(slice, offset, 8, "magic bytes")

      # Check magic
      magic = slice[offset, 8]
      unless magic == "CRDFA001".to_slice
        raise DeserializeError.new("Invalid magic bytes")
      end
      offset += 8

      # Read version
      ensure_bytes_available(slice, offset, 4, "version")
      version = read_u32(slice, offset, endianness)
      unless version == 1 || version == 2 || version == 3 || version == 4
        raise DeserializeError.new("Unsupported version: #{version}")
      end
      offset += 4

      # Read flags
      ensure_bytes_available(slice, offset, 4, "flags")
      flags = flags_from_u32(read_u32(slice, offset, endianness))
      offset += 4

      # Read state count
      ensure_bytes_available(slice, offset, 4, "state count")
      state_count = read_u32(slice, offset, endianness).to_i32
      offset += 4

      # Read start states
      ensure_bytes_available(slice, offset, 8, "start states")
      start_unanchored_unsigned = read_u32(slice, offset, endianness)
      start_unanchored = StateID.new(unsigned_to_signed(start_unanchored_unsigned))
      offset += 4
      start_anchored_unsigned = read_u32(slice, offset, endianness)
      start_anchored = StateID.new(unsigned_to_signed(start_anchored_unsigned))
      offset += 4

      start_table = nil
      if version >= 2
        unanchored_states = {} of Start => StateID
        anchored_states = {} of Start => StateID
        Start.each do |start_kind|
          ensure_bytes_available(slice, offset, 4, "unanchored start state")
          start_id = StateID.new(unsigned_to_signed(read_u32(slice, offset, endianness)))
          offset += 4
          unanchored_states[start_kind] = start_id
        end
        Start.each do |start_kind|
          ensure_bytes_available(slice, offset, 4, "anchored start state")
          start_id = StateID.new(unsigned_to_signed(read_u32(slice, offset, endianness)))
          offset += 4
          anchored_states[start_kind] = start_id
        end
        pattern_states = {} of PatternID => Hash(Start, StateID)
        if version >= 4
          ensure_bytes_available(slice, offset, 4, "pattern start state count")
          pattern_state_count = read_u32(slice, offset, endianness).to_i32
          offset += 4
          pattern_state_count.times do
            ensure_bytes_available(slice, offset, 4, "pattern start pattern id")
            pattern_id = PatternID.new(read_u32(slice, offset, endianness).to_i32)
            offset += 4
            states = {} of Start => StateID
            Start.each do |start_kind|
              ensure_bytes_available(slice, offset, 4, "pattern start state")
              start_id = StateID.new(unsigned_to_signed(read_u32(slice, offset, endianness)))
              offset += 4
              states[start_kind] = start_id
            end
            pattern_states[pattern_id] = states
          end
        end
        start_table = StartTable.new(
          flags.is_anchored ? StartKind::Anchored : StartKind::Both,
          start_unanchored,
          start_anchored,
          unanchored_states,
          anchored_states,
          pattern_states
        )
      end

      # Read byte classes count
      ensure_bytes_available(slice, offset, 4, "byte class count")
      byte_classes_count = read_u32(slice, offset, endianness).to_i32
      offset += 4

      # Read byte class mapping
      ensure_bytes_available(slice, offset, 256, "byte class map")
      class_mapping = Array.new(256) do
        byte_class = slice[offset].to_i32
        offset += 1
        byte_class
      end

      # Create ByteClasses object
      byte_classes_obj = ByteClasses.from_mapping(class_mapping, byte_classes_count)

      stride2 = 0
      stride = 1
      while stride < byte_classes_obj.alphabet_len
        stride <<= 1
        stride2 += 1
      end

      if start_unanchored.to_i >= 0
        start_unanchored = StateID.new(start_unanchored.to_i >> stride2)
        validate_serialized_state_id!(start_unanchored, state_count, "unanchored start state")
      end
      if start_anchored.to_i >= 0
        start_anchored = StateID.new(start_anchored.to_i >> stride2)
        validate_serialized_state_id!(start_anchored, state_count, "anchored start state")
      end
      if start_table
        start_table = start_table.remap do |id|
          remapped = StateID.new(id.to_i >> stride2)
          validate_serialized_state_id!(remapped, state_count, "start table state")
          remapped
        end
      end

      # Read states
      states = Array(State).new(state_count)
      state_count.times do |state_index|
        # Read state ID
        ensure_bytes_available(slice, offset, 4, "state id")
        id_unsigned = read_u32(slice, offset, endianness)
        id = StateID.new(unsigned_to_signed(id_unsigned))
        offset += 4
        validate_serialized_state_id!(id, state_count, "state id")

        # Read transitions
        ensure_bytes_available(slice, offset, 4, "transition count")
        trans_count = read_u32(slice, offset, endianness).to_i32
        offset += 4
        unless trans_count == byte_classes_count
          raise DeserializeError.new("invalid transition count #{trans_count} for state #{state_index}")
        end
        ensure_bytes_available(slice, offset, trans_count * 4, "state transitions")
        next_states = Array.new(trans_count) do
          next_id_unsigned = read_u32(slice, offset, endianness)
          offset += 4
          next_id = StateID.new(unsigned_to_signed(next_id_unsigned))
          validate_serialized_state_id!(next_id, state_count, "transition state")
          next_id
        end

        # Read match patterns
        ensure_bytes_available(slice, offset, 4, "match count")
        match_count = read_u32(slice, offset, endianness).to_i32
        offset += 4
        ensure_bytes_available(slice, offset, match_count * 4, "match pattern ids")
        match_patterns = Array.new(match_count) do
          PatternID.new(read_u32(slice, offset, endianness).to_i32)
        end
        offset += match_count * 4

        # Read look sets and flags
        ensure_bytes_available(slice, offset, 14, "state metadata")
        look_need = LookSet.new(read_u32(slice, offset, endianness))
        offset += 4
        look_have = LookSet.new(read_u32(slice, offset, endianness))
        offset += 4
        is_from_word = slice[offset] != 0
        offset += 1
        is_half_crlf = slice[offset] != 0
        offset += 1
        eoi_next_unsigned = read_u32(slice, offset, endianness)
        eoi_next = StateID.new(unsigned_to_signed(eoi_next_unsigned))
        offset += 4
        validate_serialized_state_id!(eoi_next, state_count, "EOI transition state")

        # Create state
        state = State.new(id, trans_count, look_need, look_have, is_from_word, is_half_crlf)
        state.next = next_states
        state.match = match_patterns
        state.eoi_next = eoi_next
        states << state
      end

      if st = start_table
        start_table = StartTable.new(
          st.kind,
          st.unanchored,
          st.anchored,
          st.unanchored_states,
          st.anchored_states,
          st.pattern_states,
          compute_universal_start(states, st.unanchored_states),
          compute_universal_start(states, st.anchored_states)
        )
      end

      # Read accelerators
      ensure_bytes_available(slice, offset, 4, "accelerator count")
      accel_count = read_u32(slice, offset, endianness).to_i32
      offset += 4
      unless accel_count == state_count
        raise DeserializeError.new("invalid accelerator count #{accel_count}, expected #{state_count}")
      end
      accelerators = Array.new(accel_count) do
        ensure_bytes_available(slice, offset, 4, "accelerator length")
        accel_size = read_u32(slice, offset, endianness).to_i32
        offset += 4
        ensure_bytes_available(slice, offset, accel_size, "accelerator bytes")
        accel = slice[offset, accel_size]
        offset += accel_size
        accel
      end

      # Read quit set
      ensure_bytes_available(slice, offset, 32, "quit byte set")
      quit_bytes = slice[offset, 32]
      offset += 32
      quitset = ByteSet.from_bytes(quit_bytes)

      # Create DFA
      dfa = DFA.new(states, nil, start_unanchored, byte_classes_obj, start_anchored, accelerators, nil, quitset, flags, start_table)

      {dfa, offset}
    end

    private def self.read_u32(slice : Bytes, offset : Int32, endianness : Symbol) : UInt32
      case endianness
      when :little
        slice[offset].to_u32 |
          (slice[offset + 1].to_u32 << 8) |
          (slice[offset + 2].to_u32 << 16) |
          (slice[offset + 3].to_u32 << 24)
      when :big
        (slice[offset].to_u32 << 24) |
          (slice[offset + 1].to_u32 << 16) |
          (slice[offset + 2].to_u32 << 8) |
          slice[offset + 3].to_u32
      when :native
        read_u32(slice, offset, :little)
      else
        raise "Unsupported endianness: #{endianness}"
      end
    end

    private def self.read_u64(slice : Bytes, offset : Int32, endianness : Symbol) : UInt64
      case endianness
      when :little
        value = 0_u64
        (0..7).each do |i|
          value |= slice[offset + i].to_u64 << (i * 8)
        end
        value
      when :big
        value = 0_u64
        (0..7).each do |i|
          value |= slice[offset + i].to_u64 << ((7 - i) * 8)
        end
        value
      when :native
        read_u64(slice, offset, :little)
      else
        raise "Unsupported endianness: #{endianness}"
      end
    end

    private def self.unsigned_to_signed(unsigned : UInt32) : Int32
      if unsigned >= 0x80000000_u32
        # Negative value stored as two's complement
        -((0xFFFFFFFF_u32 - unsigned + 1).to_i32)
      else
        unsigned.to_i32
      end
    end

    # Serialize this DFA to bytes in little-endian format
    # Returns a tuple of (bytes, bytes_written)
    def to_bytes_little_endian : Tuple(Bytes, Int32)
      to_bytes_with_endianness(:little)
    end

    # Serialize this DFA to bytes in big-endian format
    # Returns a tuple of (bytes, bytes_written)
    def to_bytes_big_endian : Tuple(Bytes, Int32)
      to_bytes_with_endianness(:big)
    end

    # Serialize this DFA to bytes in native-endian format
    # Returns a tuple of (bytes, bytes_written)
    def to_bytes_native_endian : Tuple(Bytes, Int32)
      to_bytes_with_endianness(:native)
    end

    # Serialize this DFA into the given buffer in little-endian format.
    # Returns the number of bytes written or raises when the buffer is too small.
    def write_to_little_endian(dst : Bytes) : Int32
      write_to_with_endianness(dst, :little)
    end

    # Serialize this DFA into the given buffer in big-endian format.
    # Returns the number of bytes written or raises when the buffer is too small.
    def write_to_big_endian(dst : Bytes) : Int32
      write_to_with_endianness(dst, :big)
    end

    # Serialize this DFA into the given buffer in native-endian format.
    # Returns the number of bytes written or raises when the buffer is too small.
    def write_to_native_endian(dst : Bytes) : Int32
      write_to_with_endianness(dst, :native)
    end

    # Return the number of bytes required to serialize this DFA.
    def write_to_len : Int32
      to_bytes_native_endian[1]
    end

    private def to_bytes_with_endianness(endianness : Symbol) : Tuple(Bytes, Int32)
      # Calculate total size needed
      total_size = 0

      # Header: magic (8 bytes), version (4 bytes), flags (4 bytes)
      total_size += 8 + 4 + 4

      # State count (4 bytes), start_unanchored (4 bytes), start_anchored (4 bytes)
      total_size += 4 + 4 + 4
      total_size += (Start.len * 2 * 4)
      total_size += 4
      total_size += @st.pattern_states.size * (4 + Start.len * 4)

      # Byte classes count (4 bytes) + byte class mapping (256 bytes)
      total_size += 4 + 256

      # For each state:
      @states.each do |state|
        # id (4 bytes), transitions count (4 bytes), match patterns count (4 bytes)
        total_size += 4 + 4 + 4
        # transitions (each 4 bytes)
        total_size += state.next.size * 4
        # match patterns (each 4 bytes)
        total_size += state.match.size * 4
        # look_need (4 bytes), look_have (4 bytes), is_from_word (1 byte), is_half_crlf (1 byte), eoi_next (4 bytes)
        total_size += 4 + 4 + 1 + 1 + 4
      end

      # Accelerators: count (4 bytes) + for each accelerator: length (4 bytes) + bytes
      total_size += 4
      @accelerators.each do |accel|
        total_size += 4 + accel.size
      end

      # Quit set: 32 bytes (256 bits / 8)
      total_size += 32

      # Allocate buffer
      buffer = Bytes.new(total_size)
      offset = 0

      # Write magic "CRDFA001"
      buffer[offset, 8].copy_from("CRDFA001".to_slice)
      offset += 8

      # Write version
      write_u32(4, buffer, offset, endianness)
      offset += 4

      # Write flags
      write_u32(flags_to_u32, buffer, offset, endianness)
      offset += 4

      # Write state count
      write_u32(@states.size.to_u32, buffer, offset, endianness)
      offset += 4

      # Write start states
      start_unanchored_value = @start_unanchored.to_i
      start_unanchored_unsigned = start_unanchored_value < 0 ? (0xFFFFFFFF_u32 + start_unanchored_value + 1).to_u32 : start_unanchored_value.to_u32
      write_u32(start_unanchored_unsigned, buffer, offset, endianness)
      offset += 4

      start_anchored_value = @start_anchored.to_i
      start_anchored_unsigned = start_anchored_value < 0 ? (0xFFFFFFFF_u32 + start_anchored_value + 1).to_u32 : start_anchored_value.to_u32
      write_u32(start_anchored_unsigned, buffer, offset, endianness)
      offset += 4

      Start.each do |start_kind|
        write_u32((@st.unanchored_states[start_kind]? || @st.unanchored).to_i.to_u32, buffer, offset, endianness)
        offset += 4
      end
      Start.each do |start_kind|
        write_u32((@st.anchored_states[start_kind]? || @st.anchored).to_i.to_u32, buffer, offset, endianness)
        offset += 4
      end
      write_u32(@st.pattern_states.size.to_u32, buffer, offset, endianness)
      offset += 4
      @st.pattern_states.each do |pattern_id, states|
        write_u32(pattern_id.to_i.to_u32, buffer, offset, endianness)
        offset += 4
        Start.each do |start_kind|
          write_u32((states[start_kind]? || states[Start::Text]).to_i.to_u32, buffer, offset, endianness)
          offset += 4
        end
      end

      # Write byte classes count
      write_u32(@byte_classes.to_u32, buffer, offset, endianness)
      offset += 4

      # Write byte class mapping
      (0..255).each do |byte|
        buffer[offset] = @byte_classifier[byte].to_u8
        offset += 1
      end

      # Write states
      @states.each do |state|
        # Write state ID
        id_value = state.id.to_i
        id_unsigned = id_value < 0 ? (0xFFFFFFFF_u32 + id_value + 1).to_u32 : id_value.to_u32
        write_u32(id_unsigned, buffer, offset, endianness)
        offset += 4

        # Write transitions count and transitions
        write_u32(state.next.size.to_u32, buffer, offset, endianness)
        offset += 4
        state.next.each do |next_id|
          # Convert signed to unsigned, preserving negative values as large positive values
          value = next_id.to_i
          unsigned_value = value < 0 ? (0xFFFFFFFF_u32 + value + 1).to_u32 : value.to_u32
          write_u32(unsigned_value, buffer, offset, endianness)
          offset += 4
        end

        # Write match patterns count and patterns
        write_u32(state.match.size.to_u32, buffer, offset, endianness)
        offset += 4
        state.match.each do |pattern_id|
          write_u32(pattern_id.to_i.to_u32, buffer, offset, endianness)
          offset += 4
        end

        # Write look sets and flags
        write_u32(state.look_need.to_u32, buffer, offset, endianness)
        offset += 4
        write_u32(state.look_have.to_u32, buffer, offset, endianness)
        offset += 4
        buffer[offset] = state.is_from_word? ? 1_u8 : 0_u8
        offset += 1
        buffer[offset] = state.is_half_crlf? ? 1_u8 : 0_u8
        offset += 1
        eoi_next_value = state.eoi_next.to_i
        eoi_next_unsigned = eoi_next_value < 0 ? (0xFFFFFFFF_u32 + eoi_next_value + 1).to_u32 : eoi_next_value.to_u32
        write_u32(eoi_next_unsigned, buffer, offset, endianness)
        offset += 4
      end

      # Write accelerators
      write_u32(@accelerators.size.to_u32, buffer, offset, endianness)
      offset += 4
      @accelerators.each do |accel|
        write_u32(accel.size.to_u32, buffer, offset, endianness)
        offset += 4
        buffer[offset, accel.size].copy_from(accel)
        offset += accel.size
      end

      # Write quit set (32 bytes for 256 bits)
      quit_bytes = @quitset.to_bytes
      buffer[offset, 32].copy_from(quit_bytes)
      offset += 32

      {buffer, offset}
    end

    private def write_to_with_endianness(dst : Bytes, endianness : Symbol) : Int32
      bytes, written = to_bytes_with_endianness(endianness)
      if dst.size < written
        raise SerializeError.new("buffer too small: need #{written} bytes, got #{dst.size}")
      end
      dst[0, written].copy_from(bytes[0, written])
      written
    end

    private def write_u32(value : UInt32, buffer : Bytes, offset : Int32, endianness : Symbol)
      case endianness
      when :little
        buffer[offset] = (value & 0xFF).to_u8
        buffer[offset + 1] = ((value >> 8) & 0xFF).to_u8
        buffer[offset + 2] = ((value >> 16) & 0xFF).to_u8
        buffer[offset + 3] = ((value >> 24) & 0xFF).to_u8
      when :big
        buffer[offset] = ((value >> 24) & 0xFF).to_u8
        buffer[offset + 1] = ((value >> 16) & 0xFF).to_u8
        buffer[offset + 2] = ((value >> 8) & 0xFF).to_u8
        buffer[offset + 3] = (value & 0xFF).to_u8
      when :native
        # Native is little-endian on most systems
        write_u32(value, buffer, offset, :little)
      end
    end

    private def write_u64(value : UInt64, buffer : Bytes, offset : Int32, endianness : Symbol)
      case endianness
      when :little
        (0..7).each do |i|
          buffer[offset + i] = ((value >> (i * 8)) & 0xFF).to_u8
        end
      when :big
        (0..7).each do |i|
          buffer[offset + i] = ((value >> ((7 - i) * 8)) & 0xFF).to_u8
        end
      when :native
        write_u64(value, buffer, offset, :little)
      end
    end

    def start : StateID
      @start_unanchored
    end

    private def flags_to_u32 : UInt32
      value = 0_u32
      value |= 1_u32 if @flags.premultiplied
      value |= 1_u32 << 1 if @flags.has_empty
      value |= 1_u32 << 2 if @flags.has_byte_classes
      value |= 1_u32 << 3 if @flags.is_anchored
      value |= 1_u32 << 4 if @flags.is_leftmost
      value |= 1_u32 << 5 if @flags.is_utf8
      value |= 1_u32 << 6 if @flags.has_prefilter
      value |= 1_u32 << 7 if @flags.is_always_start_anchored
      value
    end

    private def self.flags_from_u32(value : UInt32) : DFAFlags
      DFAFlags.new(
        premultiplied: (value & 1_u32) != 0,
        has_empty: (value & (1_u32 << 1)) != 0,
        has_byte_classes: (value & (1_u32 << 2)) != 0,
        is_anchored: (value & (1_u32 << 3)) != 0,
        is_leftmost: (value & (1_u32 << 4)) != 0,
        is_utf8: (value & (1_u32 << 5)) != 0,
        has_prefilter: (value & (1_u32 << 6)) != 0,
        is_always_start_anchored: (value & (1_u32 << 7)) != 0
      )
    end

    private def self.detect_serialized_endianness(slice : Bytes) : Symbol
      if slice.size < 12
        raise DeserializeError.new("serialized DFA too short")
      end

      little = read_u32(slice, 8, :little)
      return :little if supported_serialized_version?(little)

      big = read_u32(slice, 8, :big)
      return :big if supported_serialized_version?(big)

      raise DeserializeError.new("Unsupported version: #{little}")
    end

    private def self.supported_serialized_version?(version : UInt32) : Bool
      version == 1 || version == 2 || version == 3 || version == 4
    end

    private def self.ensure_bytes_available(slice : Bytes, offset : Int32, len : Int32, what : String) : Nil
      if len < 0 || offset < 0 || offset + len > slice.size
        raise DeserializeError.new("serialized DFA too short while reading #{what}")
      end
    end

    private def self.validate_serialized_state_id!(id : StateID, state_count : Int32, what : String) : Nil
      unless 0 <= id.to_i < state_count
        raise DeserializeError.new("invalid #{what}: #{id.to_i}")
      end
    end

    def self.compute_universal_start(states : Array(State), start_states : Hash(Start, StateID)) : StateID?
      ids = start_states.values.uniq
      return nil if ids.empty?

      representative = ids.first
      representative_state = states[representative.to_i]
      if ids.all? { |id| states_equivalent?(representative_state, states[id.to_i]) }
        representative
      else
        nil
      end
    end

    private def self.states_equivalent?(left : State, right : State) : Bool
      left.next == right.next &&
        left.match == right.match &&
        left.eoi_next == right.eoi_next
    end

    # Get number of states
    def size : Int32
      @states.size
    end

    # Get state by ID
    def [](id : StateID) : State
      state_idx = id.to_i
      if tt = @tt
        state_idx = tt.to_index(id)
      end
      @states[state_idx]
    end

    # Remove dead states (unreachable or can't reach accept state)
    def remove_dead_states : DFA
      # Forward reachable from start
      forward = Set{@start_unanchored}
      stack = [@start_unanchored]
      while !stack.empty?
        state_id = stack.pop
        state_idx = state_id.to_i
        if tt = @tt
          state_idx = tt.to_index(state_id)
        end
        current_state = @states[state_idx]
        current_state.next.each do |next_id|
          if !is_terminal_state?(next_id) && !forward.includes?(next_id)
            forward.add(next_id)
            stack.push(next_id)
          end
        end
      end

      # Backward reachable from accepting states
      backward = Set(StateID).new
      # Build reverse transitions
      reverse = Array(Set(StateID)).new(@states.size) { Set(StateID).new }
      @states.each_with_index do |state, i|
        state.next.each do |next_id|
          if !is_terminal_state?(next_id)
            next_index = if tt = @tt
                           tt.to_index(next_id)
                         else
                           next_id.to_i
                         end
            reverse[next_index].add(state.id)
          end
        end
      end

      # Start from accepting states
      stack.clear
      @states.each do |state|
        if state.accepting?
          state_id = state.id
          backward.add(state_id)
          stack.push(state_id)
        end
      end

      # BFS from accepting states
      while !stack.empty?
        state_id = stack.pop
        state_idx = if tt = @tt
                      tt.to_index(state_id)
                    else
                      state_id.to_i
                    end
        reverse[state_idx].each do |prev_id|
          unless backward.includes?(prev_id)
            backward.add(prev_id)
            stack.push(prev_id)
          end
        end
      end

      # Live states = intersection
      live = forward & backward
      return self if live.size == @states.size

      # Create mapping from old to new state IDs
      old_to_new = {} of StateID => StateID
      new_states = [] of State
      live.to_a.sort_by(&.to_i).each_with_index do |old_id, new_index|
        new_id = StateID.new(new_index)
        old_to_new[old_id] = new_id
        # Create copy of state with new ID
        state_idx = old_id.to_i
        if tt = @tt
          state_idx = tt.to_index(old_id)
        end
        old_state = @states[state_idx]
        new_state = old_state.dup(new_id)
        new_states << new_state
      end

      # Update transitions in new states
      new_states.each do |state|
        state.next.each_with_index do |next_id, i|
          if old_to_new.has_key?(next_id)
            state.next[i] = old_to_new[next_id]
          elsif is_quit_state?(next_id)
            state.next[i] = QUIT_STATE_ID
          else
            state.next[i] = DEAD_STATE_ID
          end
        end
      end

      # Update start state
      new_start_unanchored = old_to_new[@start_unanchored]? || StateID.new(0)
      new_start_anchored = old_to_new[@start_anchored]? || new_start_unanchored

      DFA.new(new_states, nil, new_start_unanchored, @byte_classifier, new_start_anchored)
    end

    # Reduce byte classes using equivalence analysis
    def reduce_byte_classes : DFA
      byte_classes = ByteClasses.from_dfa(self)
      class_count = byte_classes.alphabet_len - 1
      new_states = @states.each_with_index.map do |state, index|
        reduced = State.new(
          StateID.new(index),
          class_count,
          state.look_need,
          state.look_have,
          state.is_from_word?,
          state.is_half_crlf?
        )
        reduced.match = state.match.dup
        reduced.eoi_next = if tt = @tt
                             StateID.new(tt.to_index(state.eoi_next))
                           else
                             state.eoi_next
                           end

        class_count.times do |klass|
          representative = byte_classes.representative(klass)
          old_class = @byte_classifier[representative]
          reduced.next[klass] = if tt = @tt
                                  StateID.new(tt.to_index(state.next[old_class]))
                                else
                                  state.next[old_class]
                                end
        end
        reduced
      end.to_a

      start_unanchored = if tt = @tt
                           StateID.new(tt.to_index(@start_unanchored))
                         else
                           @start_unanchored
                         end
      start_anchored = if tt = @tt
                         StateID.new(tt.to_index(@start_anchored))
                       else
                         @start_anchored
                       end
      start_table = if tt = @tt
                      @st.remap { |id| StateID.new(tt.to_index(id)) }
                    else
                      @st
                    end

      DFA.new(
        new_states,
        nil,
        start_unanchored,
        byte_classes,
        start_anchored,
        nil,
        @prefilter,
        @quitset,
        @flags,
        start_table
      )
    end

    # Find the longest match in the input string
    # Returns tuple of (end_position, matched_pattern_ids) or nil if no match
    def find_longest_match(input : String) : Tuple(Int32, Array(PatternID))?
      find_longest_match(input.to_slice)
    end

    # Find the longest match in a byte slice
    def find_longest_match(slice : Bytes) : Tuple(Int32, Array(PatternID))?
      last_match : Tuple(Int32, Array(PatternID))? = nil
      start_state_id = search_start_state
      current_state_id = start_state_id

      idx = 0
      size = slice.size

      # Process bytes in a simple loop (uncomment for unrolled version)
      while idx < size
        next_state_id = transition(slice[idx], current_state_id)
        if is_dead_state?(next_state_id)
          break
        end

        current_state_id = next_state_id
        if is_match_state?(current_state_id)
          last_match = {idx, state_matches(current_state_id)}
        end
        idx += 1
        idx = accelerate_forward(slice, idx, current_state_id, pointerof(last_match))
      end

      if idx == size
        eoi_state = next_eoi_state(current_state_id)
        if is_match_state?(eoi_state)
          last_match = {size, state_matches(eoi_state)}
        end
      end

      last_match
    end

    # Try to search forward, returning either a match or a MatchError
    def try_search_fwd(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError
      last_match : Tuple(Int32, Array(PatternID))? = nil
      start_state_id = search_start_state
      current_state_id = start_state_id

      idx = 0
      size = slice.size

      while idx < size
        byte = slice[idx]
        next_state_id = transition(slice[idx], current_state_id)

        if is_quit_state?(next_state_id)
          return last_match || MatchError.quit(byte, idx)
        end

        break if is_dead_state?(next_state_id)

        current_state_id = next_state_id
        if is_match_state?(current_state_id)
          last_match = {idx, state_matches(current_state_id)}
        end
        idx += 1
        idx = accelerate_forward(slice, idx, current_state_id, pointerof(last_match))
      end

      if idx == size
        eoi_state = next_eoi_state(current_state_id)
        if is_match_state?(eoi_state)
          last_match = {size, state_matches(eoi_state)}
        elsif is_quit_state?(eoi_state)
          return MatchError.quit(0_u8, size)
        end
      end

      last_match
    end

    # Try to search in reverse, returning either a match or a MatchError
    def try_search_rev(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError
      last_match : Tuple(Int32, Array(PatternID))? = nil
      start_state_id = search_start_state
      current_state_id = start_state_id

      idx = slice.size - 1

      while idx >= 0
        byte = slice[idx]
        next_state_id = transition(byte, current_state_id)

        if ENV["LOGOS_DEBUG_DFA_SEARCH"]?
          puts "Reverse search: idx=#{idx}, byte=#{byte}, current_state=#{current_state_id.to_i}, next_state=#{next_state_id.to_i}"
        end

        return MatchError.quit(byte, idx) if is_quit_state?(next_state_id)

        break if is_dead_state?(next_state_id)

        current_state_id = next_state_id
        if is_match_state?(current_state_id)
          last_match = {idx + 1, state_matches(current_state_id)}
        end
        idx -= 1
        idx = accelerate_reverse(slice, idx, current_state_id, pointerof(last_match))
      end

      if idx < 0
        eoi_state = next_eoi_state(current_state_id)
        if is_match_state?(eoi_state)
          last_match = {0, state_matches(eoi_state)}
        elsif is_quit_state?(eoi_state)
          return MatchError.quit(0_u8, 0)
        end
      end

      last_match
    end

    private def search_start_state : StateID
      @flags.is_anchored ? @start_anchored : @start_unanchored
    end

    # Get next state ID for given byte
    def next_state(current : StateID, input : UInt8) : StateID
      if tt = @tt
        tt.next_state(current, input)
      else
        byte_class = @byte_classifier[input]
        @states[current.to_i].next[byte_class]
      end
    end

    # Unsafe version of next_state that assumes valid state ID
    def next_state_unchecked(current : StateID, input : UInt8) : StateID
      if tt = @tt
        tt.next_state(current, input)
      else
        byte_class = @byte_classifier[input]
        @states[current.to_i].next[byte_class]
      end
    end

    # Get next state ID for end-of-input (EOI) transition
    def next_eoi_state(current : StateID) : StateID
      if tt = @tt
        tt.next_eoi_state(current)
      else
        @states[current.to_i].eoi_next
      end
    end

    # Check if state is a match state
    def match_state?(id : StateID) : Bool
      @ms.match_state?(id)
    end

    # Alias for compatibility with Rust Automaton trait
    def is_match_state?(id : StateID) : Bool
      return false if is_dead_state?(id) || is_quit_state?(id)
      @special.is_match_state?(id) || match_state?(id)
    end

    # Check if state is a dead state
    def is_dead_state?(id : StateID) : Bool
      ::Regex::Automata::DFA.dead_state?(id)
    end

    # Check if state is a quit state
    def is_quit_state?(id : StateID) : Bool
      ::Regex::Automata::DFA.quit_state?(id) || @special.is_quit_state?(id)
    end

    # Check if state is a special state (dead, quit, match, start, etc.)
    def is_special_state?(id : StateID) : Bool
      @special.is_special_state?(id)
    end

    # Check if state is a start state
    def is_start_state?(id : StateID) : Bool
      return false if is_dead_state?(id) || is_quit_state?(id)
      @special.is_start_state?(id) || @st.start_state?(id)
    end

    # Check if state is an accelerated state
    def is_accel_state?(id : StateID) : Bool
      return false if is_dead_state?(id) || is_quit_state?(id)
      return true if @special.is_accel_state?(id)

      state_idx = id.to_i
      if tt = @tt
        state_idx = tt.to_index(id)
      end
      !@accelerators[state_idx].empty?
    end

    # Returns the number of patterns in this automaton
    def pattern_len : Int32
      @ms.pattern_len
    end

    # Returns the total number of transition entries available to each state.
    #
    # This includes the synthetic end-of-input transition in addition to the
    # byte-class transitions.
    def alphabet_len : Int32
      @tt.not_nil!.alphabet_len
    end

    # Returns the log2 stride used for premultiplied state IDs.
    def stride2 : Int32
      @tt.not_nil!.stride2
    end

    # Returns the total stride used by each row in the transition table.
    def stride : Int32
      1 << stride2
    end

    # Returns the serialized byte size of this DFA.
    #
    # This matches the current port's on-wire representation and gives a
    # concrete, implementation-backed notion of memory footprint.
    def memory_usage : Int32
      to_bytes_native_endian[0].size
    end

    # Returns the number of matches in the given state
    def match_len(id : StateID) : Int32
      @ms.match_len(id)
    end

    # Returns the pattern ID for the match at the given index in the given state
    def match_pattern(id : StateID, index : Int32) : PatternID
      @ms.match_pattern(id, index)
    end

    # Returns true if and only if this automaton is guaranteed to be valid for UTF-8 input
    def is_utf8? : Bool
      @flags.is_utf8
    end

    # Returns true if and only if this automaton is always anchored at the start
    def is_always_start_anchored? : Bool
      @flags.is_always_start_anchored
    end

    # Returns the accelerator bytes for the given state
    def accelerator(id : StateID) : Bytes
      # Return accelerator bytes for the state
      state_idx = id.to_i
      if tt = @tt
        state_idx = tt.to_index(id)
      end
      @accelerators[state_idx]
    end

    # Try to search for overlapping matches forward
    def try_search_overlapping_fwd(slice : Bytes) : Array(Tuple(Int32, Array(PatternID))) | MatchError
      matches_by_offset = {} of Int32 => Array(PatternID)
      size = slice.size

      (0..size).each do |start|
        input = Input.new(slice).span(start...size).anchored(Anchored::Yes)
        state = OverlappingState.start
        current_offset = nil.as(Int32?)
        current_patterns = [] of PatternID

        loop do
          result = try_search_overlapping_fwd(input, state)
          return result if result.is_a?(MatchError)

          half_match = state.get_match
          unless half_match
            if offset = current_offset
              merge_overlapping_patterns(matches_by_offset, offset, current_patterns)
            end
            break
          end

          if current_offset == half_match.offset
            current_patterns << half_match.pattern unless current_patterns.includes?(half_match.pattern)
          else
            if offset = current_offset
              merge_overlapping_patterns(matches_by_offset, offset, current_patterns)
            end
            current_offset = half_match.offset
            current_patterns = [half_match.pattern]
          end
        end
      end

      matches_by_offset.keys.sort.map { |offset| {offset, matches_by_offset[offset]} }
    end

    # Get universal start state for given anchored mode
    def universal_start_state(mode : Anchored) : StateID?
      @st.universal_start(mode)
    end

    # Whether DFA can match empty string
    def has_empty? : Bool
      @flags.has_empty
    end

    # Returns the prefilter for this DFA, if one exists
    def get_prefilter : Prefilter?
      @prefilter
    end

    # Attach or clear the prefilter for this DFA.
    def set_prefilter(prefilter : Prefilter?) : Nil
      @prefilter = prefilter
      @flags = DFAFlags.new(
        premultiplied: @flags.premultiplied,
        has_empty: @flags.has_empty,
        has_byte_classes: @flags.has_byte_classes,
        is_anchored: @flags.is_anchored,
        is_leftmost: @flags.is_leftmost,
        is_utf8: @flags.is_utf8,
        is_always_start_anchored: @flags.is_always_start_anchored,
        has_prefilter: !prefilter.nil?
      )
    end

    # Return a borrowed view of this DFA.
    def as_ref : DFA
      self
    end

    # Return an owned view of this DFA.
    def to_owned : DFA
      self
    end

    # Returns the start state for the given configuration
    def start_state(config : StartConfig) : StateID | StartError
      # Check for quit bytes in look-behind
      if look_behind = config.look_behind
        if @quitset.includes?(look_behind)
          return QuitStartError.new(look_behind)
        end
      end

      @st.start(config.anchored, StartTable.from_look_behind(config.look_behind), config.pattern)
    end

    # Returns the start state for a forward search (for backward compatibility)
    def start_state_forward_method(anchored : Anchored) : StateID
      config = StartConfig.new(nil, anchored)
      result = start_state(config)
      case result
      when StateID
        result
      when StartError
        # For backward compatibility, return start state even on error
        case anchored
        when Anchored::No
          @st.unanchored
        when Anchored::Yes
          @st.anchored
        else
          @st.unanchored
        end
      end
    end

    # Returns the start state for a reverse search (for backward compatibility)
    def start_state_reverse(anchored : Anchored) : StateID
      # For now, use same as forward
      start_state_forward_method(anchored)
    end

    # Map byte to its equivalence class
    private def byte_to_class(byte : UInt8) : Int32
      @byte_classifier[byte]
    end

    private def transition(byte : UInt8, current_state_id : StateID) : StateID
      if tt = @tt
        tt.next_state(current_state_id, byte)
      else
        byte_class = @byte_classifier[byte]
        @states[current_state_id.to_i].next[byte_class]
      end
    end

    private def state_matches(id : StateID) : Array(PatternID)
      count = match_len(id)
      Array.new(count) { |index| match_pattern(id, index) }
    end

    private def merge_overlapping_patterns(matches_by_offset : Hash(Int32, Array(PatternID)), offset : Int32, patterns : Array(PatternID)) : Nil
      merged = matches_by_offset[offset]? || [] of PatternID
      patterns.each do |pattern|
        next if merged.includes?(pattern)

        index = merged.bsearch_index { |existing| existing >= pattern } || merged.size
        merged.insert(index, pattern)
      end
      matches_by_offset[offset] = merged
    end

    private def accelerate_forward(slice : Bytes, idx : Int32, state_id : StateID, last_match : Pointer(Tuple(Int32, Array(PatternID))?)?) : Int32
      return idx if idx >= slice.size

      needles = accelerator(state_id)
      return idx if needles.empty?

      advanced = idx
      case needles.size
      when 1
        needle = needles[0]
        while advanced < slice.size && slice[advanced] != needle
          advanced += 1
        end
      when 2
        needle1 = needles[0]
        needle2 = needles[1]
        while advanced < slice.size
          byte = slice[advanced]
          break if byte == needle1 || byte == needle2
          advanced += 1
        end
      else
        needle1 = needles[0]
        needle2 = needles[1]
        needle3 = needles[2]
        while advanced < slice.size
          byte = slice[advanced]
          break if byte == needle1 || byte == needle2 || byte == needle3
          advanced += 1
        end
      end

      if advanced > idx && is_match_state?(state_id) && last_match
        last_match.value = {advanced, state_matches(state_id)}
      end
      advanced
    end

    private def accelerate_reverse(slice : Bytes, idx : Int32, state_id : StateID, last_match : Pointer(Tuple(Int32, Array(PatternID))?)) : Int32
      return idx if idx < 0

      needles = accelerator(state_id)
      return idx if needles.empty?

      advanced = idx
      case needles.size
      when 1
        needle = needles[0]
        while advanced >= 0 && slice[advanced] != needle
          advanced -= 1
        end
      when 2
        needle1 = needles[0]
        needle2 = needles[1]
        while advanced >= 0
          byte = slice[advanced]
          break if byte == needle1 || byte == needle2
          advanced -= 1
        end
      else
        needle1 = needles[0]
        needle2 = needles[1]
        needle3 = needles[2]
        while advanced >= 0
          byte = slice[advanced]
          break if byte == needle1 || byte == needle2 || byte == needle3
          advanced -= 1
        end
      end

      if advanced < idx && is_match_state?(state_id)
        last_match.value = {advanced + 1, state_matches(state_id)}
      end
      advanced
    end

    private def build_special : Special
      special = Special.new
      special.set_quit_id(if tt = @tt
        tt.to_state_id(QUIT_STATE_ID.to_i)
      else
        QUIT_STATE_ID
      end)

      @states.each_with_index do |state, index|
        state_id = if tt = @tt
                     tt.to_state_id(index)
                   else
                     StateID.new(index)
                   end

        special.add_match(state_id) unless state.match.empty?
        special.add_start(state_id) if @st.start_state?(state_id)
        special.add_accel(state_id) unless @accelerators[index].empty?
      end
      special
    end
  end

  # Subset construction builder
  class Builder
    record StateMeta,
      nfa_set : Set(StateID),
      look_have : LookSet,
      look_need : LookSet,
      is_from_word : Bool,
      is_half_crlf : Bool,
      matches : Array(PatternID)

    @nfa : NFA::NFA?
    @dfa_states : Array(State)
    @dfa_state_count : Int32
    @dfa_state_metas : Array(StateMeta)
    @state_map : Hash(Tuple(Set(StateID), LookSet, Bool, Bool, Array(PatternID)), StateID) # (NFA state set, look_have, is_from_word, is_half_crlf, delayed matches) -> DFA state ID
    @byte_classes : ByteClasses
    @transition_table : TransitionTable
    @nfa_has_word : Bool
    @nfa_has_unicode_word : Bool
    @nfa_has_crlf : Bool
    @config : Config
    @quitset : ByteSet
    @hir_compiler : HirCompiler
    @syntax_config : ::Regex::Syntax::ParserBuilder?
    @start_unanchored : StateID?
    @start_anchored : StateID?

    # Create a new builder with default configuration
    def self.new : Builder
      Builder.new(Config.new)
    end

    # Create a new builder from an NFA
    def self.from_nfa(nfa : NFA::NFA, config : Config = Config.new) : Builder
      Builder.new(config, nfa: nfa)
    end

    # Configure the builder with a new configuration
    def configure(config : Config) : Builder
      Builder.new(config, nfa: @nfa, hir_compiler: @hir_compiler, syntax_config: @syntax_config)
    end

    # Configure the builder using a block
    def configure(&block : Config -> Config) : Builder
      config = block.call(@config.dup)
      Builder.new(config, nfa: @nfa, hir_compiler: @hir_compiler, syntax_config: @syntax_config)
    end

    # Configure the Thompson NFA compiler
    def thompson(&block : HirCompilerConfig -> HirCompilerConfig) : Builder
      config = @config
      hir_compiler_config = HirCompilerConfig.new.which_captures(NFA::WhichCaptures::None)
      hir_compiler_config = block.call(hir_compiler_config)
      hir_compiler = HirCompiler.new(hir_compiler_config)
      Builder.new(config, nfa: @nfa, hir_compiler: hir_compiler, syntax_config: @syntax_config)
    end

    # Configure the syntax parser used before HIR compilation.
    def syntax(&block : ::Regex::Syntax::ParserBuilder -> ::Regex::Syntax::ParserBuilder) : Builder
      syntax_config = block.call((@syntax_config || ::Regex::Syntax::ParserBuilder.new))
      Builder.new(@config, nfa: @nfa, hir_compiler: @hir_compiler, syntax_config: syntax_config)
    end

    def initialize(config : Config = Config.new, nfa : NFA::NFA? = nil, hir_compiler : HirCompiler? = nil, byte_classes : ByteClasses | Int32 = 256, syntax_config : ::Regex::Syntax::ParserBuilder? = nil)
      @config = config
      @quitset = config.quitset
      @nfa = nfa
      @hir_compiler = hir_compiler || HirCompiler.new(HirCompilerConfig.new.which_captures(NFA::WhichCaptures::None))
      @syntax_config = syntax_config

      # Precompute whether NFA contains word boundary or CRLF assertions.
      @nfa_has_word = false
      @nfa_has_unicode_word = false
      @nfa_has_crlf = false
      if current_nfa = @nfa
        current_nfa.states.each do |state|
          next unless state.is_a?(NFA::Look)

          case state.kind
          when NFA::Look::Kind::WordBoundaryAscii, NFA::Look::Kind::NonWordBoundaryAscii
            @nfa_has_word = true
          when NFA::Look::Kind::WordBoundaryUnicode, NFA::Look::Kind::NonWordBoundaryUnicode
            @nfa_has_word = true
            @nfa_has_unicode_word = true
          when NFA::Look::Kind::StartLF,
               NFA::Look::Kind::EndLF,
               NFA::Look::Kind::StartCRLF,
               NFA::Look::Kind::EndCRLF
            @nfa_has_crlf = true
          when NFA::Look::Kind::StartText, NFA::Look::Kind::EndText, NFA::Look::Kind::EndTextWithNewline
            # Text anchors do not require extra CRLF bookkeeping here.
          end
        end
      end

      # Implicitly enable Unicode word boundaries if all non-ASCII bytes are quit bytes
      if !config.unicode_word_boundary? && all_non_ascii_bytes_are_quit?(@quitset)
        # Enable Unicode word boundaries
        @config = config.unicode_word_boundary(true)
        if ENV["LOGOS_DEBUG_DFA_BUILD"]?
          puts "Implicitly enabled Unicode word boundaries because all non-ASCII bytes are quit bytes"
        end
      end

      if @nfa_has_unicode_word
        unless @config.unicode_word_boundary?
          raise BuildError.new("cannot build DFAs for regexes with Unicode word boundaries; switch to ASCII word boundaries, or heuristically enable Unicode word boundaries or use a different regex engine")
        end
        @quitset = add_non_ascii_quit_bytes(@quitset)
      end

      # Create byte classes with quit bytes in separate classes
      @byte_classes = case byte_classes
                      when ByteClasses
                        # If we already have byte classes, we need to ensure quit bytes are separate
                        # For now, just use the provided classes
                        byte_classes
                      when Int32
                        if @quitset.empty?
                          ByteClasses.identity
                        else
                          ByteClasses.with_quitset(@quitset)
                        end
                      else
                        raise "Unreachable"
                      end
      @dfa_states = [] of State
      @transition_table = TransitionTable.new(@byte_classes, DFA.compute_stride2(@byte_classes), 2)
      @dfa_state_count = 2
      @dfa_state_metas = [
        StateMeta.new(Set(StateID).new, LookSet.new, LookSet.new, false, false, [] of PatternID),
        StateMeta.new(Set(StateID).new, LookSet.new, LookSet.new, false, false, [] of PatternID),
      ]
      @state_map = {} of Tuple(Set(StateID), LookSet, Bool, Bool, Array(PatternID)) => StateID
      @start_unanchored = nil
      @start_anchored = nil
    end

    # Build DFA from NFA using subset construction
    # Build DFA from a pattern string
    def build(pattern : String) : DFA
      # Parse pattern to HIR
      hir = syntax_parser.parse(pattern)

      # Compile HIR to NFA
      nfa = @hir_compiler.compile(hir)

      # Build DFA from NFA
      Builder.from_nfa(nfa, @config).build
    rescue ex : ::Regex::Syntax::AST::Error | ::Regex::Syntax::Hir::Error
      raise BuildError.new(ex.message)
    end

    # Build a DFA from multiple pattern strings
    def build_many(patterns : Array(String)) : DFA
      # Parse patterns to HIRs
      hirs = patterns.map do |pattern|
        syntax_parser.parse(pattern)
      end

      # Compile HIRs to NFA
      nfa = @hir_compiler.compile_multi(hirs)

      # Build DFA from NFA
      Builder.from_nfa(nfa, @config).build
    rescue ex : ::Regex::Syntax::AST::Error | ::Regex::Syntax::Hir::Error
      raise BuildError.new(ex.message)
    end

    # Compute accelerators for DFA states
    private def compute_accelerators(state_count : Int32, tt : TransitionTable, byte_classes : ByteClasses) : Array(Bytes)
      accelerators = Array.new(state_count) { Bytes.empty }

      state_count.times do |idx|
        # Skip dead and quit states
        next if idx == DEAD_STATE_ID.to_i || idx == QUIT_STATE_ID.to_i

        # Analyze if state can be accelerated
        accelerator = analyze_acceleration(StateID.new(idx), tt, byte_classes)
        unless accelerator.empty?
          accelerators[idx] = accelerator
        end
      end

      accelerators
    end

    # Analyze a state to see if it can be accelerated
    # Returns accelerator bytes if state can be accelerated, empty array otherwise
    # Ported from Rust's State.accelerate() method
    private def analyze_acceleration(state_id : StateID, tt : TransitionTable, byte_classes : ByteClasses) : Bytes
      # We just try to add bytes to our accelerator. Once adding fails
      # (because we've added too many bytes), then give up.
      accelerator_bytes = [] of UInt8

      # Check each byte class (transition)
      (0...(byte_classes.alphabet_len - 1)).each do |byte_class|
        next_state = StateID.new(tt.to_index(tt.next_state_by_class(tt.to_state_id(state_id.to_i), byte_class)))

        # Skip self-transitions (id == self.id())
        next if next_state == state_id

        # This byte class causes exit from the state
        # Add all bytes in this equivalence class to accelerator
        (0..255).each do |byte|
          if byte_classes[byte] == byte_class
            # Check if we can add this byte
            # Max 3 bytes in accelerator (per Rust Accel::add())
            if accelerator_bytes.size >= 3
              return Bytes.empty # Too many bytes, can't accelerate
            end

            # Reject ASCII space as a poor accelerator (per Rust implementation)
            if byte == ' '.ord
              return Bytes.empty # ASCII space is a poor accelerator
            end

            # Check if byte already in accelerator (Rust asserts this doesn't happen)
            if accelerator_bytes.includes?(byte.to_u8)
              # In Rust, this would panic. We'll just skip duplicate bytes.
              next
            end

            # Add byte to accelerator
            accelerator_bytes << byte.to_u8
          end
        end
      end

      # Return accelerator if we have any bytes
      if accelerator_bytes.empty?
        Bytes.empty
      else
        # Note: Rust doesn't sort the bytes, they're added in the order encountered
        # Convert to Bytes
        slice = Bytes.new(accelerator_bytes.size)
        accelerator_bytes.each_with_index do |byte, i|
          slice[i] = byte
        end
        slice
      end
    end

    # Build DFA from the configured NFA
    def build : DFA
      raise "No NFA configured. Use build(pattern) or provide an NFA to the builder." unless @nfa

      nfa = @nfa.not_nil!

      unanchored_start_id = nil
      anchored_start_id = nil
      unanchored_start_nfa = nil
      anchored_start_nfa = nil
      unanchored_start_states = {} of Start => StateID
      anchored_start_states = {} of Start => StateID
      pattern_start_states = {} of PatternID => Hash(Start, StateID)

      case @config.start_kind
      when StartKind::Both, StartKind::Unanchored
        unanchored_start_nfa = valid_nfa_start(nfa.start_unanchored)
        unanchored_start_states = build_start_states(unanchored_start_nfa)
        unanchored_start_id = unanchored_start_states[Start::Text]
        @start_unanchored = unanchored_start_id
      end

      case @config.start_kind
      when StartKind::Both, StartKind::Anchored
        anchored_start_nfa = valid_nfa_start(nfa.start_anchored, fallback: unanchored_start_nfa)
        anchored_start_states = build_start_states(anchored_start_nfa)
        if (source_id = unanchored_start_id) && @config.start_kind == StartKind::Both
          anchored_start_states = clone_start_states_if_needed(anchored_start_states, source_id)
        end
        anchored_start_id = anchored_start_states[Start::Text]
        @start_anchored = anchored_start_id
      end

      # DFA constructor requires at least unanchored start state
      # If unanchored start state wasn't created (start_kind == Anchored),
      # use anchored start state as unanchored
      unless unanchored_start_id
        unanchored_start_id = anchored_start_id
        @start_unanchored = unanchored_start_id
      end

      # If anchored start state wasn't created, use unanchored as anchored
      unless anchored_start_id
        anchored_start_id = unanchored_start_id
        @start_anchored = anchored_start_id
      end

      # At this point, both should be non-nil
      unanchored_start_id = unanchored_start_id.not_nil!
      anchored_start_id = anchored_start_id.not_nil!

      if @config.starts_for_each_pattern?
        fallback_pattern_start = anchored_start_nfa || unanchored_start_nfa || valid_nfa_start(nfa.start_unanchored)
        nfa.start_pattern.each_with_index do |pattern_start, index|
          starts = build_start_states(valid_nfa_start(pattern_start, fallback: fallback_pattern_start))
          if source_id = unanchored_start_id
            starts = clone_start_states_if_needed(starts, source_id)
          end
          pattern_start_states[PatternID.new(index)] = starts
        end
      end

      # Process queue of unprocessed DFA states
      queue = [] of StateID
      processed = Set(StateID).new

      if unanchored_start_id
        queue << unanchored_start_id
        processed.add(unanchored_start_id)
      end

      if anchored_start_id && anchored_start_id != unanchored_start_id && !processed.includes?(anchored_start_id)
        queue << anchored_start_id
        processed.add(anchored_start_id)
      end

      pattern_start_states.each_value do |starts|
        starts.each_value do |start_id|
          next if processed.includes?(start_id)
          queue << start_id
          processed.add(start_id)
        end
      end

      unanchored_start_lookup = {} of StateID => Start
      unanchored_start_states.each do |start_kind, start_id|
        unanchored_start_lookup[start_id] = start_kind
      end

      while !queue.empty?
        dfa_id = queue.pop
        if ENV["LOGOS_DEBUG_DFA_BUILD"]? && @dfa_state_count % 10 == 0
          puts "DFA build: processing state #{dfa_id.to_i}, total states #{@dfa_state_count}, queue size #{queue.size}"
        end

        meta = @dfa_state_metas[dfa_id.to_i]?
        next unless meta
        nfa_set = meta.nfa_set
        look_have = meta.look_have
        look_need = meta.look_need
        is_from_word = meta.is_from_word
        is_half_crlf = meta.is_half_crlf

        # For each byte class, compute transition
        (@byte_classes.alphabet_len - 1).times do |byte_class|
          byte = @byte_classes.representative(byte_class)
          next_set = Set(StateID).new
          current_look_have = look_have

          # Look-ahead assertions based on the current byte.
          if byte == '\n'.ord.to_u8
            current_look_have = current_look_have.insert(Look::EndLF)
            if !is_half_crlf
              current_look_have = current_look_have.insert(Look::EndCRLF)
            end
          elsif byte == '\r'.ord.to_u8
            current_look_have = current_look_have.insert(Look::EndCRLF)
          end

          if @nfa_has_crlf && is_half_crlf && byte != '\n'.ord.to_u8
            current_look_have = current_look_have.insert(Look::StartCRLF)
          end

          if @nfa_has_word
            if is_from_word != ::Regex::Automata.is_word_byte(byte)
              current_look_have = current_look_have.insert(Look::WordAscii).remove(Look::WordAsciiNegate)
              if @nfa_has_unicode_word
                current_look_have = current_look_have.insert(Look::WordUnicode).remove(Look::WordUnicodeNegate)
              end
            else
              current_look_have = current_look_have.remove(Look::WordAscii).insert(Look::WordAsciiNegate)
              if @nfa_has_unicode_word
                current_look_have = current_look_have.remove(Look::WordUnicode).insert(Look::WordUnicodeNegate)
              end
            end
          end

          # Update satisfied look mask for the next position
          # Start assertions (^, \A) are only true at position 0
          # After consuming a byte, we're no longer at start
          next_look_have = look_have.remove(Look::StartLF).remove(Look::Start).remove(Look::StartCRLF)

          # Start of line assertions are true after a line terminator.
          if byte == '\n'.ord.to_u8
            next_look_have = next_look_have.insert(Look::StartLF)
            if @nfa_has_crlf
              next_look_have = next_look_have.insert(Look::StartCRLF)
            end
          end

          # Word boundary assertions are computed per transition.
          next_look_have = next_look_have.remove(Look::WordAscii).remove(Look::WordAsciiNegate)
          if @nfa_has_unicode_word
            next_look_have = next_look_have.remove(Look::WordUnicode).remove(Look::WordUnicodeNegate)
          end

          # Determine next is_from_word flag (for word boundary detection)
          next_is_from_word = @nfa_has_word && ::Regex::Automata.is_word_byte(byte)
          next_is_half_crlf = @nfa_has_crlf && byte == '\r'.ord.to_u8

          # Recompute the closure for every transition so that contextual
          # assertions like word boundaries and line anchors are evaluated from
          # the current byte boundary instead of only when a coarse look_need
          # summary happens to detect it.
          effective_nfa_set = nfa.epsilon_closure_with_look(nfa_set, current_look_have)

          next_set.clear
          effective_nfa_set.each do |nfa_id|
            transitions = nfa.transitions(nfa_id, byte)
            transitions.each do |next_nfa_id|
              next_set.add(next_nfa_id)
            end
          end

          # Compute next set closure (needed for both quit check and regular transition)
          next_set_closure = nfa.epsilon_closure_with_look(next_set, next_look_have)

          # Check for quit bytes first (they overrule regex matching)
          if !@quitset.empty? && is_quit_byte_class?(byte_class)
            # If we have quit bytes and this byte class corresponds to a quit byte,
            # transition to quit state (overrules any regex matching)
            if ENV["LOGOS_DEBUG_DFA_BUILD"]?
              puts "Setting transition for byte class #{byte_class} to QUIT_STATE_ID for state #{dfa_id.to_i} (quit byte overrides regex)"
            end
            @transition_table.set_transition_by_class(@transition_table.to_state_id(dfa_id.to_i), byte_class, @transition_table.to_state_id(QUIT_STATE_ID.to_i))
          else
            delayed_matches = collect_matches(effective_nfa_set)
            if !next_set_closure.empty? || !delayed_matches.empty?
              key = {next_set_closure, next_look_have, next_is_from_word, next_is_half_crlf, delayed_matches}
              next_id = @state_map[key]?
              if next_id.nil?
                next_id = add_dfa_state(next_set, next_look_have, next_is_from_word, next_is_half_crlf, delayed_matches)
                unless processed.includes?(next_id)
                  queue << next_id
                  processed.add(next_id)
                end
              end
              @transition_table.set_transition_by_class(@transition_table.to_state_id(dfa_id.to_i), byte_class, @transition_table.to_state_id(next_id.to_i))
            else
              # No transition from this NFA state set for this byte class.
              # In an unanchored search, consuming a byte should leave us in the
              # appropriate contextual start state for the next position so that
              # look-behind sensitive assertions like word boundaries and line
              # anchors can still begin matching later in the haystack.
              if unanchored_start_lookup.has_key?(dfa_id)
                next_start_kind = StartTable.from_look_behind(byte)
                next_start_id = unanchored_start_states[next_start_kind]? || unanchored_start_states[Start::Text]
                @transition_table.set_transition_by_class(
                  @transition_table.to_state_id(dfa_id.to_i),
                  byte_class,
                  @transition_table.to_state_id(next_start_id.to_i)
                )
              end
              # Otherwise, default dead-state transition remains in place.
            end
          end
        end
      end

      # Compute EOI transitions for each DFA state.
      initial_size = @dfa_state_count
      (0...initial_size).each do |idx|
        meta = @dfa_state_metas[idx]?
        next unless meta
        nfa_set = meta.nfa_set
        look_have = meta.look_have
        is_from_word = meta.is_from_word
        is_half_crlf = meta.is_half_crlf

        eoi_look_have = look_have.insert(Look::End).insert(Look::EndLF)
        if @nfa_has_crlf || is_half_crlf
          eoi_look_have = eoi_look_have.insert(Look::EndCRLF)
        end
        if @nfa_has_word
          if is_from_word
            eoi_look_have = eoi_look_have.insert(Look::WordAscii).remove(Look::WordAsciiNegate)
            if @nfa_has_unicode_word
              eoi_look_have = eoi_look_have.insert(Look::WordUnicode).remove(Look::WordUnicodeNegate)
            end
          else
            eoi_look_have = eoi_look_have.remove(Look::WordAscii).insert(Look::WordAsciiNegate)
            if @nfa_has_unicode_word
              eoi_look_have = eoi_look_have.remove(Look::WordUnicode).insert(Look::WordUnicodeNegate)
            end
          end
        end

        delayed_matches = collect_matches(nfa.epsilon_closure_with_look(nfa_set, eoi_look_have))
        eoi_id = add_dfa_state(nfa_set, eoi_look_have, is_from_word, false, delayed_matches)
        @transition_table.set_eoi_transition(@transition_table.to_state_id(idx), @transition_table.to_state_id(eoi_id.to_i))
      end

      # Compute accelerators if enabled
      @dfa_state_metas, @transition_table, unanchored_start_id, anchored_start_id, unanchored_start_states, anchored_start_states, pattern_start_states = reorder_special_states(
        @dfa_state_count,
        @dfa_state_metas,
        @transition_table,
        unanchored_start_id,
        anchored_start_id,
        unanchored_start_states,
        anchored_start_states,
        pattern_start_states
      )
      accelerators = if @config.accelerate?
                       compute_accelerators(@dfa_state_count, @transition_table, @byte_classes)
                     else
                       Array.new(@dfa_state_count) { Bytes.empty }
                     end
      @dfa_state_metas, @transition_table, unanchored_start_id, anchored_start_id, unanchored_start_states, anchored_start_states, pattern_start_states, accelerators = reorder_accelerated_states(
        @dfa_state_count,
        @dfa_state_metas,
        @transition_table,
        unanchored_start_id,
        anchored_start_id,
        unanchored_start_states,
        anchored_start_states,
        pattern_start_states,
        accelerators
      )
      @dfa_state_count = @dfa_state_metas.size
      @dfa_states = materialize_states_from_metadata(@dfa_state_metas, @transition_table)
      patch_contextual_start_transitions(@transition_table, unanchored_start_states)
      patch_contextual_start_transitions(@transition_table, anchored_start_states)
      @dfa_states = materialize_states_from_metadata(@dfa_state_metas, @transition_table)

      # Create DFA flags from config
      flags = DFAFlags.new(
        has_byte_classes: true,
        has_empty: dfa_has_empty?(unanchored_start_states, anchored_start_states),
        is_utf8: nfa.utf8?,
        is_leftmost: @config.match_kind == MatchKind::LeftmostFirst,
        is_anchored: @config.start_kind == StartKind::Anchored,
        is_always_start_anchored: nfa.start_anchored == nfa.start_unanchored
      )
      st = StartTable.new(
        @config.start_kind,
        unanchored_start_id,
        anchored_start_id,
        unanchored_start_states,
        anchored_start_states,
        pattern_start_states,
        DFA.compute_universal_start(@dfa_states, unanchored_start_states),
        DFA.compute_universal_start(@dfa_states, anchored_start_states)
      )

      dfa = DFA.new(@dfa_states, @transition_table, unanchored_start_id, @byte_classes, anchored_start_id, accelerators, nil, @quitset, flags, st)

      # The state shuffling done before this point always assumes that start
      # states should be marked as "special," even though it isn't the
      # default configuration. State shuffling is complex enough as it is,
      # so it's simpler to just "fix" our special state ID ranges to not
      # include starting states after-the-fact.
      if !@config.specialize_start_states?
        dfa.@special.set_no_special_start_states
      end

      if prefilter = @config.prefilter
        dfa.set_prefilter(prefilter)
      end

      dfa = Minimizer.new(dfa).run if @config.get_minimize

      if limit = @config.get_dfa_size_limit
        if dfa.memory_usage > limit
          raise BuildError.new("DFA exceeded size limit of #{limit} bytes", size_limit_exceeded: true)
        end
      end

      dfa
    end

    private def syntax_parser : ::Regex::Syntax::Parser
      (@syntax_config || ::Regex::Syntax::ParserBuilder.new).build
    end

    private def valid_nfa_start(start : StateID, fallback : StateID? = nil) : StateID
      return start if @nfa && start.to_i >= 0 && start.to_i < @nfa.not_nil!.states.size
      fallback || StateID.new(0)
    end

    private def dfa_has_empty?(unanchored_start_states : Hash(Start, StateID), anchored_start_states : Hash(Start, StateID)) : Bool
      start_ids = (unanchored_start_states.values + anchored_start_states.values).uniq
      start_ids.any? do |id|
        meta = @dfa_state_metas[id.to_i]
        !meta.matches.empty? || !@dfa_state_metas[@transition_table.to_index(@transition_table.next_eoi_state(@transition_table.to_state_id(id.to_i)))].matches.empty?
      end
    end

    private def build_start_states(nfa_start : StateID) : Hash(Start, StateID)
      start_set = Set{nfa_start}
      starts = {} of Start => StateID

      text_look_have, text_is_from_word = start_look_have_for(Start::Text)
      text_start = add_dfa_state(start_set, text_look_have, text_is_from_word, false, [] of PatternID)
      Start.each do |start_kind|
        starts[start_kind] = text_start
      end

      if @nfa_has_crlf
        {Start::LineLF, Start::LineCR}.each do |start_kind|
          look_have, is_from_word = start_look_have_for(start_kind)
          starts[start_kind] = add_dfa_state(start_set, look_have, is_from_word, false, [] of PatternID)
        end
      end

      if @nfa_has_word
        {Start::NonWordByte, Start::WordByte}.each do |start_kind|
          look_have, is_from_word = start_look_have_for(start_kind)
          starts[start_kind] = add_dfa_state(start_set, look_have, is_from_word, false, [] of PatternID)
        end
        starts[Start::CustomLineTerminator] = starts[Start::NonWordByte]
      end

      starts
    end

    private def clone_start_states_if_needed(starts : Hash(Start, StateID), source_id : StateID) : Hash(Start, StateID)
      cloned = {} of Start => StateID
      clone_map = {} of StateID => StateID
      starts.each do |start_kind, id|
        cloned[start_kind] = if id == source_id
                               clone_map[id] ||= clone_dfa_state(id)
                             else
                               id
                             end
      end
      cloned
    end

    private def clone_dfa_state(source_id : StateID) : StateID
      source_meta = @dfa_state_metas[source_id.to_i]
      new_id = StateID.new(@dfa_state_count)
      @dfa_state_metas << source_meta
      @transition_table.add_state
      @transition_table.copy_state(@transition_table.to_state_id(source_id.to_i), @transition_table.to_state_id(new_id.to_i))
      @dfa_state_count += 1
      check_determinize_size_limit!
      new_id
    end

    private def start_look_have_for(start_kind : Start) : Tuple(LookSet, Bool)
      look_have = LookSet.new
      is_from_word = false

      case start_kind
      when Start::Text
        look_have = look_have.insert(Look::Start).insert(Look::StartLF)
        look_have = look_have.insert(Look::StartCRLF) if @nfa_has_crlf
      when Start::LineLF
        look_have = look_have.insert(Look::StartLF)
        look_have = look_have.insert(Look::StartCRLF) if @nfa_has_crlf
      when Start::LineCR
        look_have = look_have.insert(Look::StartCRLF) if @nfa_has_crlf
      when Start::WordByte
        is_from_word = true
        look_have = look_have.insert(Look::WordAscii)
        look_have = look_have.insert(Look::WordUnicode) if @nfa_has_unicode_word
      when Start::NonWordByte, Start::CustomLineTerminator
        look_have = look_have.insert(Look::WordAsciiNegate)
        look_have = look_have.insert(Look::WordUnicodeNegate) if @nfa_has_unicode_word
      end
      {look_have, is_from_word}
    end

    private def add_dfa_state(nfa_set : Set(StateID), look_have : LookSet = LookSet.new, is_from_word : Bool = false, is_half_crlf : Bool = false, matches : Array(PatternID)? = nil) : StateID
      raise "No NFA configured" unless @nfa
      nfa = @nfa.not_nil!

      # First compute epsilon closure with the given satisfied look conditions
      closure = nfa.epsilon_closure_with_look(nfa_set, look_have)
      state_matches = matches || collect_matches(closure)

      # Check if we already have a DFA state for this (closure, look_have, delayed matches)
      key = {closure, look_have, is_from_word, is_half_crlf, state_matches}
      if existing = @state_map[key]?
        return existing
      end

      dfa_id = StateID.new(@dfa_state_count)

      # Compute look need set from NFA states that are look-around assertions
      look_need = LookSet.new
      nfa_set.each do |nfa_id|
        nfa_state = nfa.states[nfa_id.to_i]
        if nfa_state.is_a?(NFA::Look)
          look_need = look_need.union(look_from_nfa_kind(nfa_state.kind))
        end
      end
      meta = StateMeta.new(closure, look_have, look_need, is_from_word, is_half_crlf, state_matches)

      # Check if any NFA state in set is a match
      if ENV["LOGOS_DEBUG_DFA"]?
        puts "DFA state #{dfa_id.to_i}: NFA set size #{nfa_set.size}, look_need #{look_need}, look_have #{look_have}"
        nfa_set.each do |nfa_id|
          nfa_state = nfa.states[nfa_id.to_i]
          puts "  NFA state #{nfa_id.to_i}: #{nfa_state.class} #{nfa_state.is_a?(NFA::Match) ? "(match pattern #{nfa_state.pattern_id.to_i}, next=#{nfa_state.next.inspect})" : ""}"
        end
        state_matches.each do |pattern_id|
          puts "DFA state #{dfa_id.to_i}: adding match for pattern #{pattern_id.to_i}"
        end
      end

      @dfa_state_metas << meta
      @transition_table.add_state
      @dfa_state_count += 1
      @state_map[key] = dfa_id
      check_determinize_size_limit!
      dfa_id
    end

    private def collect_matches(closure : Set(StateID)) : Array(PatternID)
      raise "No NFA configured" unless @nfa
      nfa = @nfa.not_nil!

      matches = [] of PatternID
      closure.each do |nfa_id|
        nfa_state = nfa.states[nfa_id.to_i]
        next unless nfa_state.is_a?(NFA::Match)
        next unless nfa_state.next.nil?

        idx = matches.bsearch_index { |pid| pid >= nfa_state.pattern_id } || matches.size
        if idx == matches.size || matches[idx] != nfa_state.pattern_id
          matches.insert(idx, nfa_state.pattern_id)
        end
      end
      matches
    end

    private def is_quit_byte_class?(byte_class : Int32) : Bool
      # Check if this byte class contains any quit bytes
      # Since we're using ByteClasses.with_quitset, all quit bytes should be in class 0
      # But we should check more carefully
      return false if @quitset.empty?

      # For now, assume quit bytes are in class 0
      # This is true if we're using ByteClasses.with_quitset
      byte_class == 0
    end

    private def look_from_nfa_kind(kind : NFA::Look::Kind) : LookSet
      case kind
      when NFA::Look::Kind::StartLF
        LookSet.from_look(Look::StartLF)
      when NFA::Look::Kind::EndLF
        LookSet.from_look(Look::EndLF)
      when NFA::Look::Kind::StartCRLF
        LookSet.from_look(Look::StartCRLF)
      when NFA::Look::Kind::EndCRLF
        LookSet.from_look(Look::EndCRLF)
      when NFA::Look::Kind::WordBoundaryAscii
        LookSet.from_look(Look::WordAscii)
      when NFA::Look::Kind::NonWordBoundaryAscii
        LookSet.from_look(Look::WordAsciiNegate)
      when NFA::Look::Kind::WordBoundaryUnicode
        LookSet.from_look(Look::WordUnicode)
      when NFA::Look::Kind::NonWordBoundaryUnicode
        LookSet.from_look(Look::WordUnicodeNegate)
      when NFA::Look::Kind::StartText
        LookSet.from_look(Look::Start)
      when NFA::Look::Kind::EndText, NFA::Look::Kind::EndTextWithNewline
        LookSet.from_look(Look::End)
      else
        raise "Unreachable look kind: #{kind}"
      end
    end

    private def add_non_ascii_quit_bytes(quitset : ByteSet) : ByteSet
      expanded = quitset
      (0x80..0xFF).each do |byte|
        expanded = expanded.add(byte.to_u8)
      end
      expanded
    end

    private def patch_contextual_start_transitions(tt : TransitionTable, start_states : Hash(Start, StateID)) : Nil
      start_ids = start_states.values.uniq
      return if start_ids.empty?
      start_tt_ids = start_ids.map { |id| tt.to_state_id(id.to_i) }.to_set

      text_start_id = start_states[Start::Text]? || start_ids.first
      text_tt_id = tt.to_state_id(text_start_id.to_i)

      start_ids.each do |start_id|
        start_kind = start_states.key_for(start_id)
        next unless start_kind

        tt_id = tt.to_state_id(start_id.to_i)
        (@byte_classes.alphabet_len - 1).times do |byte_class|
          next_state = tt.next_state_by_class(tt_id, byte_class)
          text_next = tt.next_state_by_class(text_tt_id, byte_class)

          byte = @byte_classes.representative(byte_class)
          if ::Regex::Automata::DFA.dead_state?(next_state)
            if contextual_start_kind?(start_kind) &&
               !::Regex::Automata::DFA.dead_state?(text_next) &&
               !start_tt_ids.includes?(text_next)
              tt.set_transition_by_class(tt_id, byte_class, text_next)
            else
              next_start_kind = StartTable.from_look_behind(byte)
              next_start_id = start_states[next_start_kind]? || text_start_id
              tt.set_transition_by_class(tt_id, byte_class, tt.to_state_id(next_start_id.to_i))
            end
            next
          end

          next unless contextual_start_kind?(start_kind)

          next if ::Regex::Automata::DFA.dead_state?(text_next)
          next unless start_tt_ids.includes?(next_state)
          next if start_tt_ids.includes?(text_next)

          tt.set_transition_by_class(tt_id, byte_class, text_next)
        end
      end
    end

    private def contextual_start_kind?(start_kind : Start) : Bool
      case start_kind
      when Start::NonWordByte, Start::LineLF, Start::LineCR, Start::CustomLineTerminator
        true
      else
        false
      end
    end

    private def all_non_ascii_bytes_are_quit?(quitset : ByteSet) : Bool
      # Check if all bytes 0x80-0xFF are in the quit set
      (0x80..0xFF).all? do |b|
        quitset.includes?(b.to_u8)
      end
    end

    private def check_determinize_size_limit! : Nil
      return unless limit = @config.get_determinize_size_limit
      if determinize_memory_usage > limit
        raise BuildError.new("determinization exceeded size limit of #{limit} bytes", size_limit_exceeded: true)
      end
    end

    private def determinize_memory_usage : Int64
      usage = (@dfa_state_metas.size * 64 + @state_map.size * 32).to_i64
      @dfa_state_metas.each do |meta|
        usage += (meta.nfa_set.size * 8).to_i64
        usage += (meta.matches.size * 4).to_i64
      end
      usage
    end

    private def reorder_special_states(state_count : Int32, metas : Array(StateMeta), tt : TransitionTable, unanchored_start_id : StateID, anchored_start_id : StateID, unanchored_start_states : Hash(Start, StateID), anchored_start_states : Hash(Start, StateID), pattern_start_states : Hash(PatternID, Hash(Start, StateID))) : Tuple(Array(StateMeta), TransitionTable, StateID, StateID, Hash(Start, StateID), Hash(Start, StateID), Hash(PatternID, Hash(Start, StateID)))
      start_indices = (unanchored_start_states.values + anchored_start_states.values + pattern_start_states.values.flat_map(&.values)).map(&.to_i).uniq
      match_indices = [] of Int32
      start_only_indices = [] of Int32
      other_indices = [] of Int32

      state_count.times do |index|
        if index == DEAD_STATE_ID.to_i || index == QUIT_STATE_ID.to_i
          next
        end
        if start_indices.includes?(index)
          if !metas[index].matches.empty?
            other_indices << index
          else
            start_only_indices << index
          end
        elsif !metas[index].matches.empty?
          match_indices << index
        else
          other_indices << index
        end
      end

      new_order = [DEAD_STATE_ID.to_i, QUIT_STATE_ID.to_i] + match_indices + start_only_indices + other_indices
      old_to_new = {} of Int32 => Int32
      new_order.each_with_index do |old_index, new_index|
        old_to_new[old_index] = new_index
      end

      reordered_metas = Array(StateMeta).new(state_count)
      reordered_tt = TransitionTable.new(tt.classes, tt.stride2, state_count)
      new_order.each_with_index do |old_index, new_index|
        reordered_metas << metas[old_index]

        old_tt_id = tt.to_state_id(old_index)
        new_tt_id = reordered_tt.to_state_id(new_index)
        (tt.classes.alphabet_len - 1).times do |byte_class|
          old_next = tt.next_state_by_class(old_tt_id, byte_class)
          reordered_tt.set_transition_by_class(new_tt_id, byte_class, reordered_tt.to_state_id(old_to_new[tt.to_index(old_next)]))
        end
        reordered_tt.set_eoi_transition(new_tt_id, reordered_tt.to_state_id(old_to_new[tt.to_index(tt.next_eoi_state(old_tt_id))]))
      end

      {
        reordered_metas,
        reordered_tt,
        StateID.new(old_to_new[unanchored_start_id.to_i]),
        StateID.new(old_to_new[anchored_start_id.to_i]),
        remap_start_state_ids(unanchored_start_states, old_to_new),
        remap_start_state_ids(anchored_start_states, old_to_new),
        remap_pattern_start_state_ids(pattern_start_states, old_to_new),
      }
    end

    private def reorder_accelerated_states(state_count : Int32, metas : Array(StateMeta), tt : TransitionTable, unanchored_start_id : StateID, anchored_start_id : StateID, unanchored_start_states : Hash(Start, StateID), anchored_start_states : Hash(Start, StateID), pattern_start_states : Hash(PatternID, Hash(Start, StateID)), accelerators : Array(Bytes)) : Tuple(Array(StateMeta), TransitionTable, StateID, StateID, Hash(Start, StateID), Hash(Start, StateID), Hash(PatternID, Hash(Start, StateID)), Array(Bytes))
      start_indices = (unanchored_start_states.values + anchored_start_states.values + pattern_start_states.values.flat_map(&.values)).map(&.to_i).to_set
      match_nonaccel = [] of Int32
      match_accel = [] of Int32
      normal_accel = [] of Int32
      start_accel = [] of Int32
      start_nonaccel = [] of Int32
      normal_nonaccel = [] of Int32

      state_count.times do |index|
        next if index == DEAD_STATE_ID.to_i || index == QUIT_STATE_ID.to_i

        is_start = start_indices.includes?(index)
        is_match = !metas[index].matches.empty? && !is_start
        is_accel = !accelerators[index].empty?

        if is_match
          if is_accel
            match_accel << index
          else
            match_nonaccel << index
          end
        elsif is_start
          if is_accel
            start_accel << index
          else
            start_nonaccel << index
          end
        elsif is_accel
          normal_accel << index
        else
          normal_nonaccel << index
        end
      end

      new_order = [DEAD_STATE_ID.to_i, QUIT_STATE_ID.to_i] +
                  match_nonaccel + match_accel + normal_accel + start_accel + start_nonaccel + normal_nonaccel
      return {metas, tt, unanchored_start_id, anchored_start_id, unanchored_start_states, anchored_start_states, pattern_start_states, accelerators} if new_order == (0...state_count).to_a

      old_to_new = {} of Int32 => Int32
      new_order.each_with_index do |old_index, new_index|
        old_to_new[old_index] = new_index
      end

      reordered_metas = Array(StateMeta).new(state_count)
      reordered_tt = TransitionTable.new(tt.classes, tt.stride2, state_count)
      reordered_accels = Array.new(state_count) { Bytes.empty }

      new_order.each_with_index do |old_index, new_index|
        reordered_metas << metas[old_index]
        reordered_accels[new_index] = accelerators[old_index]

        old_tt_id = tt.to_state_id(old_index)
        new_tt_id = reordered_tt.to_state_id(new_index)
        (tt.classes.alphabet_len - 1).times do |byte_class|
          old_next = tt.next_state_by_class(old_tt_id, byte_class)
          reordered_tt.set_transition_by_class(new_tt_id, byte_class, reordered_tt.to_state_id(old_to_new[tt.to_index(old_next)]))
        end
        reordered_tt.set_eoi_transition(new_tt_id, reordered_tt.to_state_id(old_to_new[tt.to_index(tt.next_eoi_state(old_tt_id))]))
      end

      {
        reordered_metas,
        reordered_tt,
        StateID.new(old_to_new[unanchored_start_id.to_i]),
        StateID.new(old_to_new[anchored_start_id.to_i]),
        remap_start_state_ids(unanchored_start_states, old_to_new),
        remap_start_state_ids(anchored_start_states, old_to_new),
        remap_pattern_start_state_ids(pattern_start_states, old_to_new),
        reordered_accels,
      }
    end

    private def build_state_shell(id : StateID, meta : StateMeta) : State
      state = State.new(id, @byte_classes.alphabet_len - 1, meta.look_need, meta.look_have, meta.is_from_word, meta.is_half_crlf)
      state.match = meta.matches.dup
      state
    end

    private def materialize_states_from_metadata(metas : Array(StateMeta), tt : TransitionTable) : Array(State)
      states = Array(State).new(metas.size)
      metas.each_with_index do |meta, index|
        state = build_state_shell(StateID.new(index), meta)
        tt_id = tt.to_state_id(index)
        state.next = Array.new(tt.classes.alphabet_len - 1) do |byte_class|
          StateID.new(tt.to_index(tt.next_state_by_class(tt_id, byte_class)))
        end
        state.eoi_next = StateID.new(tt.to_index(tt.next_eoi_state(tt_id)))
        states << state
      end
      states
    end

    private def remap_start_state_ids(starts : Hash(Start, StateID), old_to_new : Hash(Int32, Int32)) : Hash(Start, StateID)
      starts.transform_values do |id|
        StateID.new(old_to_new[id.to_i])
      end
    end

    private def remap_pattern_start_state_ids(pattern_starts : Hash(PatternID, Hash(Start, StateID)), old_to_new : Hash(Int32, Int32)) : Hash(PatternID, Hash(Start, StateID))
      pattern_starts.transform_values do |starts|
        remap_start_state_ids(starts, old_to_new)
      end
    end
  end
end
