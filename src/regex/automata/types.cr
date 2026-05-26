module Regex::Automata
  struct SmallIndexError
    getter attempted : Int64

    def initialize(@attempted : Int64)
    end
  end

  struct SmallIndex
    include Comparable(SmallIndex)

    MAX_VALUE = Int32::MAX - 1
    MAX       = SmallIndex.new_unchecked(MAX_VALUE)
    LIMIT     = MAX_VALUE.to_i64 + 1_i64
    ZERO      = SmallIndex.new_unchecked(0)
    SIZE      = 4

    @id : Int32

    def initialize(@id : Int32)
    end

    def self.new_unchecked(index : Int) : SmallIndex
      SmallIndex.new(index.to_i32)
    end

    def self.must(index : Int) : SmallIndex
      index_i64 = index.to_i64
      raise ArgumentError.new("invalid small index") if index_i64 < 0 || index_i64 > MAX_VALUE.to_i64

      SmallIndex.new_unchecked(index_i64.to_i32)
    end

    def self.from_ne_bytes(bytes : Bytes) : SmallIndex | SmallIndexError
      raise ArgumentError.new("expected 4 bytes, got #{bytes.size}") unless bytes.size == 4

      value = IO::Memory.new(bytes).read_bytes(UInt32, IO::ByteFormat::SystemEndian)
      return SmallIndexError.new(value.to_i64) if value > MAX_VALUE.to_u32

      SmallIndex.new_unchecked(value.to_i32)
    end

    def self.from_ne_bytes_unchecked(bytes : Bytes) : SmallIndex
      raise ArgumentError.new("expected 4 bytes, got #{bytes.size}") unless bytes.size == 4

      value = IO::Memory.new(bytes).read_bytes(UInt32, IO::ByteFormat::SystemEndian)
      SmallIndex.new_unchecked(value.to_i32)
    end

    def <=>(other : self) : Int32
      @id <=> other.@id
    end

    def to_i : Int32
      @id
    end

    def to_i32 : Int32
      @id
    end

    def to_i64 : Int64
      @id.to_i64
    end

    def as_u32 : UInt32
      @id.to_u32
    end

    def one_more : Int64
      @id.to_i64 + 1_i64
    end

    def to_ne_bytes : Bytes
      bytes = Bytes.new(4)
      IO::Memory.new(bytes).write_bytes(@id.to_u32, IO::ByteFormat::SystemEndian)
      bytes
    end
  end

  # Pattern identifiers
  struct PatternID
    include Comparable(PatternID)

    MAX   = PatternID.new_unchecked(SmallIndex::MAX_VALUE)
    LIMIT = SmallIndex::LIMIT
    ZERO  = PatternID.new_unchecked(0)
    SIZE  = SmallIndex::SIZE

    @id : Int32

    def initialize(@id : Int32)
    end

    def self.new_unchecked(value : Int) : PatternID
      PatternID.new(value.to_i32)
    end

    def self.must(value : Int) : PatternID
      value_i64 = value.to_i64
      raise ArgumentError.new("invalid PatternID value") if value_i64 < 0 || value_i64 > SmallIndex::MAX_VALUE.to_i64

      PatternID.new_unchecked(value_i64.to_i32)
    end

    def self.from_ne_bytes(bytes : Bytes) : PatternID | SmallIndexError
      result = SmallIndex.from_ne_bytes(bytes)
      return PatternID.new_unchecked(result.to_i32) if result.is_a?(SmallIndex)

      result
    end

    def self.from_ne_bytes_unchecked(bytes : Bytes) : PatternID
      PatternID.new_unchecked(SmallIndex.from_ne_bytes_unchecked(bytes).to_i32)
    end

    def <=>(other : self) : Int32
      @id <=> other.@id
    end

    def to_i : Int32
      @id
    end

    def to_i32 : Int32
      @id
    end

    def to_i64 : Int64
      @id.to_i64
    end

    def as_u32 : UInt32
      @id.to_u32
    end

    def one_more : Int64
      @id.to_i64 + 1_i64
    end

    def to_ne_bytes : Bytes
      bytes = Bytes.new(4)
      IO::Memory.new(bytes).write_bytes(@id.to_u32, IO::ByteFormat::SystemEndian)
      bytes
    end
  end

  # State identifiers
  struct StateID
    include Comparable(StateID)

    MAX   = StateID.new_unchecked(SmallIndex::MAX_VALUE)
    LIMIT = SmallIndex::LIMIT
    ZERO  = StateID.new_unchecked(0)
    SIZE  = SmallIndex::SIZE

    @id : Int32

    def initialize(@id : Int32)
    end

    def self.new_unchecked(value : Int) : StateID
      StateID.new(value.to_i32)
    end

    def self.must(value : Int) : StateID
      value_i64 = value.to_i64
      raise ArgumentError.new("invalid StateID value") if value_i64 < 0 || value_i64 > SmallIndex::MAX_VALUE.to_i64

      StateID.new_unchecked(value_i64.to_i32)
    end

    def self.from_ne_bytes(bytes : Bytes) : StateID | SmallIndexError
      result = SmallIndex.from_ne_bytes(bytes)
      return StateID.new_unchecked(result.to_i32) if result.is_a?(SmallIndex)

      result
    end

    def self.from_ne_bytes_unchecked(bytes : Bytes) : StateID
      StateID.new_unchecked(SmallIndex.from_ne_bytes_unchecked(bytes).to_i32)
    end

    def <=>(other : self) : Int32
      @id <=> other.@id
    end

    def to_i : Int32
      @id
    end

    def to_i32 : Int32
      @id
    end

    def to_i64 : Int64
      @id.to_i64
    end

    def as_u32 : UInt32
      @id.to_u32
    end

    def one_more : Int64
      @id.to_i64 + 1_i64
    end

    def to_ne_bytes : Bytes
      bytes = Bytes.new(4)
      IO::Memory.new(bytes).write_bytes(@id.to_u32, IO::ByteFormat::SystemEndian)
      bytes
    end
  end

  struct NonMaxUsize
    include Comparable(NonMaxUsize)

    @value : Int32

    def self.new(value : Int32) : NonMaxUsize?
      return nil if value == Int32::MAX || value < 0

      value = value
      previous_def
    end

    def initialize(@value : Int32)
    end

    def <=>(other : self) : Int32
      @value <=> other.@value
    end

    def get : Int32
      @value
    end
  end

  # Flags describing DFA behavior and configuration
  struct DFAFlags
    # Whether the DFA is premultiplied (state IDs = index * alphabet_len)
    getter premultiplied : Bool
    # Whether the DFA can match the empty string
    getter has_empty : Bool
    # Whether the DFA has a byte class map
    getter has_byte_classes : Bool
    # Whether the DFA is anchored
    getter is_anchored : Bool
    # Whether the DFA is leftmost (priority to earliest matches)
    getter is_leftmost : Bool
    # Whether the DFA is UTF-8 aware
    getter is_utf8 : Bool
    # Whether the DFA can only produce matches starting at offset 0
    getter is_always_start_anchored : Bool
    # Whether the DFA has a prefilter
    getter has_prefilter : Bool

    def initialize(@premultiplied : Bool = false, @has_empty : Bool = false, @has_byte_classes : Bool = true, @is_anchored : Bool = false, @is_leftmost : Bool = false, @is_utf8 : Bool = false, @is_always_start_anchored : Bool = false, @has_prefilter : Bool = false)
    end
  end
end
