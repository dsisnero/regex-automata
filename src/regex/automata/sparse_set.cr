require "./types"

module Regex::Automata
  class SparseSet
    @dense : Array(StateID)
    @sparse : Array(Int32?)

    def initialize(capacity : Int32)
      @dense = [] of StateID
      @sparse = Array(Int32?).new(capacity, nil)
    end

    def resize(capacity : Int32) : Nil
      if capacity < @sparse.size
        @dense.reject! { |sid| sid.to_i >= capacity }
      end
      @sparse = Array(Int32?).new(capacity, nil)
      @dense.each_with_index do |sid, index|
        @sparse[sid.to_i] = index.to_i32
      end
    end

    def clear : Nil
      @dense.clear
      @sparse.fill(nil)
    end

    def insert(id : StateID) : Bool
      index = id.to_i
      return false if index < 0 || index >= @sparse.size
      return false if @sparse[index]?

      @sparse[index] = @dense.size.to_i32
      @dense << id
      true
    end

    def is_empty : Bool
      @dense.empty?
    end

    def empty? : Bool
      is_empty
    end

    def iter
      @dense.each
    end

    def each(& : StateID ->) : Nil
      @dense.each { |sid| yield sid }
    end

    def memory_usage : Int32
      ((@dense.size * sizeof(StateID)) + (@sparse.size * sizeof(Int32))).to_i32
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
