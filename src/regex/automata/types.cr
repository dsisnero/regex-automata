module Regex::Automata
  # Pattern identifiers
  struct PatternID
    include Comparable(PatternID)

    @id : Int32

    def initialize(@id : Int32)
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
  end

  # State identifiers
  struct StateID
    include Comparable(StateID)

    @id : Int32

    def initialize(@id : Int32)
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
