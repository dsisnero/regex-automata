require "./types"

module Regex::Automata
  class SparseSet
    @dense : Array(StateID)
    @sparse : Array(StateID)
    @len : Int32

    def initialize(capacity : Int32)
      @dense = [] of StateID
      @sparse = [] of StateID
      @len = 0
      resize(capacity)
    end

    def resize(capacity : Int32) : Nil
      raise ArgumentError.new("sparse set capacity cannot be negative") if capacity < 0
      raise ArgumentError.new("sparse set capacity cannot exceed #{StateID::LIMIT}") if capacity.to_i64 > StateID::LIMIT

      @len = 0
      if @dense.size > capacity
        while @dense.size > capacity
          @dense.pop
          @sparse.pop
        end
      else
        while @dense.size < capacity
          @dense << StateID.new(0)
          @sparse << StateID.new(0)
        end
      end
    end

    def capacity : Int32
      @sparse.size.to_i32
    end

    def len : Int32
      @len
    end

    def contains(id : StateID) : Bool
      index = id.to_i
      return false if index < 0 || index >= @sparse.size

      dense_index = @sparse[index]
      dense_index.to_i < @len && @dense[dense_index.to_i] == id
    end

    def clear : Nil
      @len = 0
    end

    def insert(id : StateID) : Bool
      index = id.to_i
      return false if index < 0 || index >= @sparse.size
      return false if contains(id)
      raise IndexError.new("sparse set capacity exceeded") if @len >= @dense.size

      @sparse[index] = StateID.new(@len)
      @dense[@len] = id
      @len += 1
      true
    end

    def is_empty : Bool
      @len == 0
    end

    def empty? : Bool
      is_empty
    end

    def iter
      @dense[0, @len].each
    end

    def each(& : StateID ->) : Nil
      @dense[0, @len].each { |sid| yield sid }
    end

    def memory_usage : Int32
      ((@dense.size * sizeof(StateID)) + (@sparse.size * sizeof(StateID))).to_i32
    end
  end

  class SparseSets
    getter set1 : SparseSet
    getter set2 : SparseSet

    def initialize(capacity : Int32)
      @set1 = SparseSet.new(capacity)
      @set2 = SparseSet.new(capacity)
    end

    def clear : Nil
      @set1.clear
      @set2.clear
    end

    def swap : Nil
      @set1, @set2 = @set2, @set1
    end

    def resize(capacity : Int32) : Nil
      @set1.resize(capacity)
      @set2.resize(capacity)
    end

    def memory_usage : Int32
      @set1.memory_usage + @set2.memory_usage
    end
  end
end
