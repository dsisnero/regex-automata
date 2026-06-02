module Regex::Automata::Determinize
  struct State
    def_equals_and_hash @bytes

    @bytes : Bytes

    def initialize(@bytes : Bytes)
    end

    def self.dead : State
      StateBuilderEmpty.new.into_matches.into_nfa.to_state
    end

    def is_match : Bool
      repr.is_match
    end

    def is_match? : Bool
      is_match
    end

    def is_from_word : Bool
      repr.is_from_word
    end

    def is_from_word? : Bool
      is_from_word
    end

    def is_half_crlf : Bool
      repr.is_half_crlf
    end

    def is_half_crlf? : Bool
      is_half_crlf
    end

    def look_have : ::Regex::Automata::LookSet
      repr.look_have
    end

    def look_need : ::Regex::Automata::LookSet
      repr.look_need
    end

    def match_len : Int32
      repr.match_len
    end

    def match_pattern(index : Int) : ::Regex::Automata::PatternID
      repr.match_pattern(index.to_i32)
    end

    def match_pattern_ids : Array(::Regex::Automata::PatternID)?
      repr.match_pattern_ids
    end

    def iter_match_pattern_ids(& : ::Regex::Automata::PatternID ->) : Nil
      repr.iter_match_pattern_ids do |pid|
        yield pid
      end
    end

    def iter_nfa_state_ids(& : ::Regex::Automata::StateID ->) : Nil
      repr.iter_nfa_state_ids do |sid|
        yield sid
      end
    end

    def memory_usage : Int32
      @bytes.size.to_i32
    end

    def to_slice : Bytes
      @bytes
    end

    def inspect(io : IO) : Nil
      io << "State("
      repr.inspect(io)
      io << ")"
    end

    private def repr : Repr
      Repr.new(@bytes)
    end
  end

  class StateBuilderEmpty
    @repr : Array(UInt8)

    def initialize
      @repr = [] of UInt8
    end

    protected def initialize(@repr : Array(UInt8))
    end

    def into_matches : StateBuilderMatches
      9.times { @repr << 0_u8 }
      StateBuilderMatches.new(@repr)
    end

    def capacity : Int32
      @repr.size.to_i32
    end

    protected def clear : Nil
      @repr.clear
    end
  end

  class StateBuilderMatches
    @repr : Array(UInt8)

    protected def initialize(@repr : Array(UInt8))
    end

    def into_nfa : StateBuilderNFA
      repr_vec.close_match_pattern_ids
      StateBuilderNFA.new(@repr, ::Regex::Automata::StateID::ZERO)
    end

    def set_is_from_word : Nil
      repr_vec.set_is_from_word
    end

    def set_is_half_crlf : Nil
      repr_vec.set_is_half_crlf
    end

    def look_have : ::Regex::Automata::LookSet
      ::Regex::Automata::LookSet.read_repr(slice[1, 4])
    end

    def set_look_have(& : ::Regex::Automata::LookSet -> ::Regex::Automata::LookSet) : Nil
      repr_vec.set_look_have do |set|
        yield set
      end
    end

    def add_match_pattern_id(pid : ::Regex::Automata::PatternID) : Nil
      repr_vec.add_match_pattern_id(pid)
    end

    def inspect(io : IO) : Nil
      io << "StateBuilderMatches("
      repr.inspect(io)
      io << ")"
    end

    protected def slice : Bytes
      Slice.new(@repr.to_unsafe, @repr.size)
    end

    private def repr : Repr
      Repr.new(slice)
    end

    private def repr_vec : ReprVec
      ReprVec.new(@repr)
    end
  end

  class StateBuilderNFA
    @repr : Array(UInt8)
    @prev_nfa_state_id : ::Regex::Automata::StateID

    protected def initialize(
      @repr : Array(UInt8),
      @prev_nfa_state_id : ::Regex::Automata::StateID,
    )
    end

    def to_state : State
      bytes = Bytes.new(@repr.size)
      @repr.each_with_index { |byte, i| bytes[i] = byte }
      State.new(bytes)
    end

    def clear : StateBuilderEmpty
      builder = StateBuilderEmpty.new(@repr)
      builder.clear
      builder
    end

    def look_need : ::Regex::Automata::LookSet
      repr.look_need
    end

    def set_look_have(& : ::Regex::Automata::LookSet -> ::Regex::Automata::LookSet) : Nil
      repr_vec.set_look_have do |set|
        yield set
      end
    end

    def set_look_need(& : ::Regex::Automata::LookSet -> ::Regex::Automata::LookSet) : Nil
      repr_vec.set_look_need do |set|
        yield set
      end
    end

    def add_nfa_state_id(sid : ::Regex::Automata::StateID) : Nil
      repr_vec.add_nfa_state_id(@prev_nfa_state_id, sid)
      @prev_nfa_state_id = sid
    end

    def as_bytes : Bytes
      Slice.new(@repr.to_unsafe, @repr.size)
    end

    def inspect(io : IO) : Nil
      io << "StateBuilderNFA("
      repr.inspect(io)
      io << ")"
    end

    private def repr : Repr
      Repr.new(as_bytes)
    end

    private def repr_vec : ReprVec
      ReprVec.new(@repr)
    end
  end

  def self.write_vari32(data : Array(UInt8), n : Int32) : Nil
    un = (((n.to_i64) << 1) ^ ((n.to_i64) >> 31)).to_u32
    write_varu32(data, un)
  end

  def self.read_vari32(data : Bytes) : Tuple(Int32, Int32)
    un, nread = read_varu32(data)
    n = (un >> 1).to_i64
    n = ~n if (un & 1_u32) != 0_u32
    {n.to_i32, nread}
  end

  def self.write_varu32(data : Array(UInt8), n : UInt32) : Nil
    value = n
    while value >= 0b1000_0000_u32
      data << ((value & 0b0111_1111_u32) | 0b1000_0000_u32).to_u8
      value >>= 7
    end
    data << value.to_u8
  end

  def self.read_varu32(data : Bytes) : Tuple(UInt32, Int32)
    n = 0_u32
    shift = 0_u32
    data.each_with_index do |byte, i|
      if byte < 0b1000_0000_u8
        return {n | (byte.to_u32 << shift), (i + 1).to_i32}
      end
      n |= (byte.to_u32 & 0b0111_1111_u32) << shift
      shift += 7
    end
    {0_u32, 0}
  end

  private class Repr
    def initialize(@bytes : Bytes)
    end

    def is_match : Bool
      (@bytes[0] & (1 << 0)) > 0
    end

    def has_pattern_ids : Bool
      (@bytes[0] & (1 << 1)) > 0
    end

    def is_from_word : Bool
      (@bytes[0] & (1 << 2)) > 0
    end

    def is_half_crlf : Bool
      (@bytes[0] & (1 << 3)) > 0
    end

    def look_have : ::Regex::Automata::LookSet
      ::Regex::Automata::LookSet.read_repr(@bytes[1, 4])
    end

    def look_need : ::Regex::Automata::LookSet
      ::Regex::Automata::LookSet.read_repr(@bytes[5, 4])
    end

    def match_len : Int32
      return 0 unless is_match
      return 1 unless has_pattern_ids

      encoded_pattern_len
    end

    def match_pattern(index : Int32) : ::Regex::Automata::PatternID
      return ::Regex::Automata::PatternID::ZERO unless has_pattern_ids

      offset = 13 + (index * ::Regex::Automata::PatternID::SIZE)
      ::Regex::Automata::PatternID.from_ne_bytes_unchecked(@bytes[offset, 4])
    end

    def match_pattern_ids : Array(::Regex::Automata::PatternID)?
      return nil unless is_match

      pids = [] of ::Regex::Automata::PatternID
      iter_match_pattern_ids { |pid| pids << pid }
      pids
    end

    def iter_match_pattern_ids(& : ::Regex::Automata::PatternID ->) : Nil
      return unless is_match
      unless has_pattern_ids
        yield ::Regex::Automata::PatternID::ZERO
        return
      end

      pids = @bytes[13, pattern_offset_end - 13]
      offset = 0
      while offset < pids.size
        yield ::Regex::Automata::PatternID.from_ne_bytes_unchecked(pids[offset, 4])
        offset += ::Regex::Automata::PatternID::SIZE
      end
    end

    def iter_nfa_state_ids(& : ::Regex::Automata::StateID ->) : Nil
      sids = @bytes[pattern_offset_end, @bytes.size - pattern_offset_end]
      prev = 0_i32
      offset = 0
      while offset < sids.size
        delta, nread = Determinize.read_vari32(sids[offset, sids.size - offset])
        sid = prev + delta
        prev = sid
        yield ::Regex::Automata::StateID.new_unchecked(sid)
        offset += nread
      end
    end

    def inspect(io : IO) : Nil
      io << "Repr("
      io << "is_match=" << is_match
      io << ", is_from_word=" << is_from_word
      io << ", is_half_crlf=" << is_half_crlf
      io << ", look_have=" << look_have
      io << ", look_need=" << look_need
      io << ", match_pattern_ids="
      ppids = match_pattern_ids
      if ppids
        io << ppids
      else
        io << "nil"
      end
      io << ", nfa_state_ids="
      sids = [] of ::Regex::Automata::StateID
      iter_nfa_state_ids { |sid| sids << sid }
      io << sids
      io << ")"
    end

    private def pattern_offset_end : Int32
      encoded = encoded_pattern_len
      return 9 if encoded == 0

      13 + (encoded * 4)
    end

    private def encoded_pattern_len : Int32
      return 0 unless has_pattern_ids

      IO::ByteFormat::SystemEndian.decode(UInt32, @bytes[9, 4]).to_i32
    end
  end

  private class ReprVec
    def initialize(@bytes : Array(UInt8))
    end

    def set_is_match : Nil
      @bytes[0] |= 1 << 0
    end

    def set_has_pattern_ids : Nil
      @bytes[0] |= 1 << 1
    end

    def set_is_from_word : Nil
      @bytes[0] |= 1 << 2
    end

    def set_is_half_crlf : Nil
      @bytes[0] |= 1 << 3
    end

    def look_have : ::Regex::Automata::LookSet
      repr.look_have
    end

    def look_need : ::Regex::Automata::LookSet
      repr.look_need
    end

    def set_look_have(& : ::Regex::Automata::LookSet -> ::Regex::Automata::LookSet) : Nil
      set = yield look_have
      bytes = Bytes.new(4)
      set.write_repr(bytes)
      4.times { |i| @bytes[1 + i] = bytes[i] }
    end

    def set_look_need(& : ::Regex::Automata::LookSet -> ::Regex::Automata::LookSet) : Nil
      set = yield look_need
      bytes = Bytes.new(4)
      set.write_repr(bytes)
      4.times { |i| @bytes[5 + i] = bytes[i] }
    end

    def add_match_pattern_id(pid : ::Regex::Automata::PatternID) : Nil
      unless repr.has_pattern_ids
        if pid == ::Regex::Automata::PatternID::ZERO
          set_is_match
          return
        end
        ::Regex::Automata::PatternID::SIZE.times { @bytes << 0_u8 }
        set_has_pattern_ids
        if repr.is_match
          Determinize.write_u32(@bytes, 0_u32)
        else
          set_is_match
        end
      end
      Determinize.write_u32(@bytes, pid.as_u32)
    end

    def close_match_pattern_ids : Nil
      return unless repr.has_pattern_ids

      patsize = ::Regex::Automata::PatternID::SIZE
      pattern_bytes = @bytes.size - 13
      raise "invalid pattern byte count" unless pattern_bytes % patsize == 0

      count = (pattern_bytes // patsize).to_u32
      write_u32_at(9, count)
    end

    def add_nfa_state_id(prev : ::Regex::Automata::StateID, sid : ::Regex::Automata::StateID) : Nil
      delta = sid.to_i32 - prev.to_i32
      Determinize.write_vari32(@bytes, delta)
    end

    private def repr : Repr
      Repr.new(Slice.new(@bytes.to_unsafe, @bytes.size))
    end

    private def write_u32_at(offset : Int32, value : UInt32) : Nil
      bytes = Bytes.new(4)
      IO::ByteFormat::SystemEndian.encode(value, bytes)
      4.times { |i| @bytes[offset + i] = bytes[i] }
    end
  end

  def self.write_u32(dst : Array(UInt8), value : UInt32) : Nil
    bytes = Bytes.new(4)
    IO::ByteFormat::SystemEndian.encode(value, bytes)
    bytes.each { |byte| dst << byte }
  end
end
