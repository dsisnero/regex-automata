module Regex::Automata
  class Pool(T)
    @create : Proc(T)
    @mutex : Mutex
    @stack : Array(T)

    def initialize(&@create : -> T)
      @mutex = Mutex.new
      @stack = [] of T
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
        @stack << value
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
