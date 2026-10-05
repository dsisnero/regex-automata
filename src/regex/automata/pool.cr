module Regex::Automata
  class Pool(T)
    @create : Proc(T)
    @mutex : Mutex
    @stack : Array(T)
    @capacity : Int32

    def initialize(capacity : Int32 = 8, &@create : -> T)
      @mutex = Mutex.new
      @stack = [] of T
      @capacity = Math.max(1, capacity)
    end

    def self.with_capacity(capacity : Int32, &create : -> T) : Pool(T)
      new(capacity, &create)
    end

    def get : PoolGuard(T)
      value = @mutex.synchronize do
        @stack.pop?
      end
      value ||= @create.call
      PoolGuard(T).new(self, value)
    end

    protected def put_value(value : T) : Nil
      @mutex.synchronize do
        @stack << value if @stack.size < @capacity
      end
    end
  end

  class PoolGuard(T)
    @pool : Pool(T)
    @value : T?

    def initialize(@pool : Pool(T), value : T)
      @value = value
    end

    def self.put(this : PoolGuard(T)) : Nil forall T
      this.put
    end

    def value : T
      @value.not_nil!
    end

    def put : Nil
      return unless value = @value

      @value = nil
      @pool.put_value(value)
    end
  end
end
