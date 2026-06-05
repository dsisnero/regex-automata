require "./automaton"
require "./dfa"

module Regex::Automata::DFA
  module Sparse
    class DFA < ::Regex::Automata::Automaton
      LABEL = "CRSFA001"

      getter dense : ::Regex::Automata::DFA::DFA

      def self.new(pattern : String) : DFA
        from_dense(::Regex::Automata::DFA::DFA.new(pattern))
      end

      def self.new_many(patterns : Array(String)) : DFA
        from_dense(::Regex::Automata::DFA::DFA.new_many(patterns))
      end

      def self.always_match : DFA
        from_dense(::Regex::Automata::DFA::DFA.always_match)
      end

      def self.never_match : DFA
        from_dense(::Regex::Automata::DFA::DFA.never_match)
      end

      def self.from_dense(dense : ::Regex::Automata::DFA::DFA) : DFA
        body = dense.to_bytes_native_endian[0]
        cloned = ::Regex::Automata::DFA::DFA.from_bytes(body)[0]
        new(cloned)
      end

      def self.from_bytes(slice : Bytes) : Tuple(DFA, Int32)
        ensure_bytes_available(slice, 0, 12, "sparse header")
        magic = slice[0, 8]
        unless magic == LABEL.to_slice
          raise DeserializeError.new("Invalid sparse magic bytes")
        end

        body_len = read_u32_le(slice, 8).to_i32
        ensure_bytes_available(slice, 12, body_len, "embedded dense DFA")
        dense, read = ::Regex::Automata::DFA::DFA.from_bytes(slice[12, body_len])
        unless read == body_len
          raise DeserializeError.new("sparse body length #{body_len} did not match dense bytes read #{read}")
        end
        {new(dense), 12 + body_len}
      end

      def initialize(@dense : ::Regex::Automata::DFA::DFA)
      end

      def as_ref : DFA
        self
      end

      def to_owned : DFA
        self.class.from_bytes(to_bytes_native_endian[0])[0]
      end

      def to_sparse : DFA
        self
      end

      def start_kind : StartKind
        @dense.st.kind
      end

      def starts_for_each_pattern : Bool
        !@dense.st.pattern_states.empty?
      end

      def byte_classes : ByteClasses
        @dense.byte_classifier
      end

      def memory_usage : Int32
        write_to_len
      end

      def set_prefilter(prefilter : Prefilter?) : Nil
        @dense.set_prefilter(prefilter)
      end

      def get_prefilter : Prefilter?
        @dense.get_prefilter
      end

      def to_bytes_little_endian : Tuple(Bytes, Int32)
        to_bytes_with_dense(@dense.to_bytes_little_endian[0])
      end

      def to_bytes_big_endian : Tuple(Bytes, Int32)
        to_bytes_with_dense(@dense.to_bytes_big_endian[0])
      end

      def to_bytes_native_endian : Tuple(Bytes, Int32)
        to_bytes_with_dense(@dense.to_bytes_native_endian[0])
      end

      def write_to_little_endian(dst : Bytes) : Int32
        write_to_with_dense(dst, @dense.to_bytes_little_endian[0])
      end

      def write_to_big_endian(dst : Bytes) : Int32
        write_to_with_dense(dst, @dense.to_bytes_big_endian[0])
      end

      def write_to_native_endian(dst : Bytes) : Int32
        write_to_with_dense(dst, @dense.to_bytes_native_endian[0])
      end

      def write_to_len : Int32
        12 + @dense.write_to_len
      end

      def next_state(current : StateID, input : UInt8) : StateID
        @dense.next_state(current, input)
      end

      def next_eoi_state(current : StateID) : StateID
        @dense.next_eoi_state(current)
      end

      def start_state(config : StartConfig) : StateID | StartError
        @dense.start_state(config)
      end

      def is_special_state?(id : StateID) : Bool
        @dense.is_special_state?(id)
      end

      def is_dead_state?(id : StateID) : Bool
        @dense.is_dead_state?(id)
      end

      def is_quit_state?(id : StateID) : Bool
        @dense.is_quit_state?(id)
      end

      def is_match_state?(id : StateID) : Bool
        @dense.is_match_state?(id)
      end

      def is_start_state?(id : StateID) : Bool
        @dense.is_start_state?(id)
      end

      def is_accel_state?(id : StateID) : Bool
        @dense.is_accel_state?(id)
      end

      def pattern_len : Int32
        @dense.pattern_len
      end

      def match_len(id : StateID) : Int32
        @dense.match_len(id)
      end

      def match_pattern(id : StateID, index : Int32) : PatternID
        @dense.match_pattern(id, index)
      end

      def has_empty? : Bool
        @dense.has_empty?
      end

      def is_utf8? : Bool
        @dense.is_utf8?
      end

      def is_always_start_anchored? : Bool
        @dense.is_always_start_anchored?
      end

      def accelerator(id : StateID) : Bytes
        @dense.accelerator(id)
      end

      def try_search_fwd(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError
        @dense.try_search_fwd(slice)
      end

      def try_search_rev(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError
        @dense.try_search_rev(slice)
      end

      def try_search_overlapping_fwd(input : Input, state : OverlappingState) : Nil | MatchError
        @dense.try_search_overlapping_fwd(input, state)
      end

      def try_search_overlapping_fwd(slice : Bytes) : Array(Tuple(Int32, Array(PatternID))) | MatchError
        @dense.try_search_overlapping_fwd(slice)
      end

      def try_search_overlapping_rev(input : Input, state : OverlappingState) : Nil | MatchError
        @dense.try_search_overlapping_rev(input, state)
      end

      def universal_start_state(anchored : Anchored) : StateID?
        @dense.universal_start_state(anchored)
      end

      private def to_bytes_with_dense(body : Bytes) : Tuple(Bytes, Int32)
        buffer = Bytes.new(12 + body.size)
        write_header(buffer, body.size)
        buffer[12, body.size].copy_from(body)
        {buffer, buffer.size}
      end

      private def write_to_with_dense(dst : Bytes, body : Bytes) : Int32
        needed = 12 + body.size
        if dst.size < needed
          raise SerializeError.new("destination buffer too small for sparse DFA: need #{needed}, got #{dst.size}")
        end
        write_header(dst, body.size)
        dst[12, body.size].copy_from(body)
        needed
      end

      private def write_header(dst : Bytes, body_size : Int32) : Nil
        dst[0, 8].copy_from(LABEL.to_slice)
        write_u32_le(dst, 8, body_size.to_u32)
      end

      private def self.ensure_bytes_available(slice : Bytes, offset : Int32, len : Int32, what : String) : Nil
        if len < 0 || offset < 0 || offset + len > slice.size
          raise DeserializeError.new("serialized sparse DFA too short while reading #{what}")
        end
      end

      private def self.read_u32_le(slice : Bytes, offset : Int32) : UInt32
        slice[offset].to_u32 |
          (slice[offset + 1].to_u32 << 8) |
          (slice[offset + 2].to_u32 << 16) |
          (slice[offset + 3].to_u32 << 24)
      end

      private def write_u32_le(dst : Bytes, offset : Int32, value : UInt32) : Nil
        dst[offset] = (value & 0xFF).to_u8
        dst[offset + 1] = ((value >> 8) & 0xFF).to_u8
        dst[offset + 2] = ((value >> 16) & 0xFF).to_u8
        dst[offset + 3] = ((value >> 24) & 0xFF).to_u8
      end
    end
  end

  class DFA
    def to_sparse : Sparse::DFA
      Sparse::DFA.from_dense(self)
    end
  end
end
