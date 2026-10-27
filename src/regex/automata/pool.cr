module Regex::Automata
  AVAILABLE_PARALLELISM = Lazy(Int32).new { System.cpu_count }

  class Pool(T)
    MAX_POOL_STACKS =     8
    UNOWNED         = 0_u64
    IN_USE          = 1_u64

    private class Stack(T)
      getter values : Array(CacheValue(T))

      def initialize
        @locked = Atomic(Bool).new(false)
        # Keep the embedded lock words in separate cache-line-sized objects.
        # Crystal has no repr(align(64)); the padding prevents adjacent
        # stacks from sharing a line even when GC allocations are contiguous.
        @cache_line_padding = StaticArray(UInt8, 64).new(0_u8)
        @values = [] of CacheValue(T)
      end

      def try_lock? : Bool
        _, acquired = @locked.compare_and_set(false, true, :acquire, :relaxed)
        acquired
      end

      def unlock : Nil
        @locked.set(false, :release)
      end
    end

    @create : Proc(T)
    @stacks : Array(Stack(T))
    @owner : Atomic(UInt64)
    @owner_val : CacheValue(T)?

    def initialize(capacity : Int32 = MAX_POOL_STACKS, &@create : -> T)
      @stacks = Array.new(Math.max(1, capacity)) { Stack(T).new }
      @owner = Atomic(UInt64).new(UNOWNED)
      @owner_val = nil
    end

    def self.with_capacity(capacity : Int32, &create : -> T) : Pool(T)
      new(capacity, &create)
    end

    def self.with_available_parallelism_capacity(&create : -> T) : Pool(T)
      new(AVAILABLE_PARALLELISM.get, &create)
    end

    def get : PoolGuard(T)
      caller = Thread.current.object_id.to_u64
      owner = @owner.get(:acquire)
      if caller == owner
        @owner.set(IN_USE, :release)
        return PoolGuard(T).owned(self, @owner_val.not_nil!, caller)
      end
      get_slow(caller, owner)
    end

    # Crystal has no deterministic destructor. This block provides Rust's
    # scope-exit return, including when the consumer raises. On the owner
    # path it also avoids allocating a Crystal guard for each search.
    def with(&)
      caller = Thread.current.object_id.to_u64
      owner = @owner.get(:acquire)
      if caller == owner
        @owner.set(IN_USE, :release)
        begin
          return yield @owner_val.not_nil!.value
        ensure
          @owner.set(caller, :release)
        end
      end

      guard = get_slow(caller, owner)
      begin
        yield guard.value
      ensure
        guard.put
      end
    end

    protected def restore_owner(owner : UInt64) : Nil
      @owner.set(owner, :release)
    end

    protected def put_value(value : CacheValue(T)) : Nil
      stack = @stacks[Thread.current.object_id.to_u64 % @stacks.size]
      10.times do
        next unless stack.try_lock?
        begin
          stack.values << value
        ensure
          stack.unlock
        end
        return
      end
    end

    private def get_slow(caller : UInt64, owner : UInt64) : PoolGuard(T)
      if owner == UNOWNED
        _, won = @owner.compare_and_set(UNOWNED, IN_USE, :acquire_release, :acquire)
        if won
          @owner_val = CacheValue(T).new(@create.call)
          return PoolGuard(T).owned(self, @owner_val.not_nil!, caller)
        end
      end

      stack = @stacks[caller % @stacks.size]
      if stack.try_lock?
        value = begin
          stack.values.pop?
        ensure
          stack.unlock
        end
        value ||= CacheValue(T).new(@create.call)
        PoolGuard(T).stack(self, value)
      else
        PoolGuard(T).stack(self, CacheValue(T).new(@create.call), discard: true)
      end
    end
  end

  class PoolGuard(T)
    @pool : Pool(T)
    @value : CacheValue(T)?
    @owner : UInt64
    @discard : Bool
    @returned : Atomic(Bool)

    private def initialize(@pool : Pool(T), @value : CacheValue(T), @owner : UInt64, @discard : Bool)
      @returned = Atomic(Bool).new(false)
    end

    def self.owned(pool : Pool(T), value : CacheValue(T), owner : UInt64) : PoolGuard(T)
      new(pool, value, owner, false)
    end

    def self.stack(pool : Pool(T), value : CacheValue(T), discard : Bool = false) : PoolGuard(T)
      new(pool, value, 0_u64, discard)
    end

    def self.put(this : PoolGuard(T)) : Nil forall T
      this.put
    end

    def value : T
      @value.not_nil!.value
    end

    def value=(value : T) : T
      @value.not_nil!.value = value
    end

    def put : Nil
      _, first = @returned.compare_and_set(false, true, :acquire_release, :acquire)
      return unless first
      value = @value.not_nil!
      @value = nil
      if @owner != 0_u64
        @pool.restore_owner(@owner)
      elsif !@discard
        @pool.put_value(value)
      end
    end
  end
end
