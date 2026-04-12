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
end
