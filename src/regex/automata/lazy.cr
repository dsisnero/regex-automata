module Regex::Automata
  # A reference wrapper permits atomic publication of any T, including Nil.
  class CacheValue(T)
    property value : T

    def initialize(@value : T)
    end
  end

  class Lazy(T)
    @create : Proc(T)
    @data : Atomic(CacheValue(T)?)

    def initialize(&@create : -> T)
      @data = Atomic(CacheValue(T)?).new(nil)
    end

    def self.get(this : Lazy(T)) : T forall T
      this.get
    end

    def get : T
      if data = @data.get(:acquire)
        return data.value
      end

      # Rust's alloc implementation allows concurrent factories. A losing
      # value is discarded; only the winning reference is ever published.
      created = CacheValue(T).new(@create.call)
      old, won = @data.compare_and_set(nil, created, :acquire_release, :acquire)
      (won ? created : old.not_nil!).value
    end
  end
end
