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
end
