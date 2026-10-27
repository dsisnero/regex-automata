require "./spec_helper"

class Regex::Automata::Meta::Regex
  def pooled_cache_id_for_spec : UInt64
    @pool.with { |cache| cache.object_id.to_u64 }
  end

  def pool_unowned_for_spec? : Bool
    @pool.unowned_for_spec?
  end
end

class Regex::Automata::Pool(T)
  def unowned_for_spec? : Bool
    @owner.get == UNOWNED
  end

  def with_current_stack_locked_for_spec(&)
    stack = @stacks[Thread.current.object_id.to_u64 % @stacks.size]
    raise "test stack already locked" unless stack.try_lock?
    begin
      yield
    ensure
      stack.unlock
    end
  end
end

describe Regex::Automata::Pool(Array(Char)) do
  it "creates fresh values when the pool is empty and reuses values after put" do
    calls = 0
    pool = Regex::Automata::Pool(Array(Char)).new do
      calls += 1
      ['a']
    end

    first = pool.get
    first.value.should eq(['a'])
    first.value << 'b'
    first.put

    second = pool.get
    second.value.should eq(['a', 'b'])
    second.put

    calls.should eq(1)
  end

  it "supports the upstream-style class put helper" do
    calls = 0
    pool = Regex::Automata::Pool(Int32).new do
      calls += 1
      7
    end

    guard = pool.get
    guard.value.should eq(7)
    Regex::Automata::PoolGuard.put(guard)

    pool.get.value.should eq(7)
    calls.should eq(1)
  end

  it "lets a guard mutate a scalar cache value" do
    pool = Regex::Automata::Pool(Int32).new { 1 }
    guard = pool.get
    guard.value = 2
    guard.put
    pool.with { |value| value.should eq(2) }
  end

  it "returns a shared guard at most once under concurrent puts" do
    pool = Regex::Automata::Pool(Array(Char)).new { ['a'] }
    guard = pool.get
    first = Thread.new { guard.put }
    second = Thread.new { guard.put }
    first.join
    second.join
    one = pool.get
    two = pool.get
    one.value.should eq(['a'])
    two.value.should eq(['a'])
    one.value.same?(two.value).should be_false
    one.put
    two.put
  end

  it "returns distinct values for simultaneous gets" do
    calls = 0
    pool = Regex::Automata::Pool(Array(Char)).new do
      calls += 1
      ['a']
    end

    g1 = pool.get
    g2 = pool.get

    g1.value << 'b'
    g2.value << 'c'

    g1.value.should eq(['a', 'b'])
    g2.value.should eq(['a', 'c'])

    g1.put
    g2.put

    calls.should eq(2)
  end

  it "coerces zero capacity to one shard without capping retained values" do
    calls = 0
    pool = Regex::Automata::Pool(Int32).with_capacity(0) do
      calls += 1
      calls
    end

    first = pool.get
    second = pool.get
    first.put
    second.put

    third = pool.get
    fourth = pool.get
    third.put
    fourth.put
    calls.should eq(2)
  end

  it "ports thread_owner_optimization from the vendor" do
    pool = Regex::Automata::Pool(Array(Char)).new { ['a'] }
    first = pool.get
    first.value << 'x'
    first.put

    workers = [] of Thread
    2.times do |index|
      suffix = index == 0 ? 'y' : 'z'
      workers << Thread.new do
        guard = pool.get
        guard.value << suffix
        guard.put
      end
    end
    workers.each(&.join)

    owned = pool.get
    owned.value.should eq(['a', 'x'])
    owned.put
  end

  it "ports thread_owner_send_drop from the vendor" do
    pool = Regex::Automata::Pool(Array(Char)).new { ['a'] }
    first = pool.get
    first.value << 'b'
    first.put

    moved = pool.get
    moved.value.should eq(['a', 'b'])
    Thread.new do
      moved.value << 'c'
      moved.put
    end.join

    owned = pool.get
    owned.value.should eq(['a', 'b', 'c'])
    owned.put
  end

  it "ports thread_owner_sync with distinct guards moved to workers" do
    pool = Regex::Automata::Pool(Array(Char)).new { ['a'] }
    first = pool.get
    second = pool.get

    left = Thread.new { first.value << 'b' }
    right = Thread.new { second.value << 'c' }
    left.join
    right.join

    first.value.should eq(['a', 'b'])
    second.value.should eq(['a', 'c'])
    first.put
    second.put
    owned = pool.get
    owned.value.should eq(['a', 'b'])
    owned.put
  end

  it "treats capacity as shard count, not a retention limit" do
    calls = 0
    pool = Regex::Automata::Pool(Int32).with_capacity(1) do
      calls += 1
      calls
    end
    first = pool.get
    second = pool.get
    first.put
    second.put
    third = pool.get
    fourth = pool.get
    third.put
    fourth.put

    calls.should eq(2)
  end

  it "uses transient values when a shard is contended and discards them" do
    calls = 0
    pool = Regex::Automata::Pool(Int32).with_capacity(1) do
      calls += 1
      calls
    end
    owner = pool.get
    pool.with_current_stack_locked_for_spec do
      transient = pool.get
      transient.value.should eq(2)
      transient.put
    end
    other = pool.get
    other.value.should eq(3)
    other.put
    owner.put
    calls.should eq(3)
  end

  it "keeps the owner scoped path independent of shard locks" do
    calls = 0
    pool = Regex::Automata::Pool(Int32).with_capacity(1) do
      calls += 1
      calls
    end
    pool.with { |value| value.should eq(1) }
    pool.with_current_stack_locked_for_spec do
      pool.with { |value| value.should eq(1) }
    end
    calls.should eq(1)
  end

  it "drops a stack value after ten failed return attempts" do
    calls = 0
    pool = Regex::Automata::Pool(Int32).with_capacity(1) do
      calls += 1
      calls
    end
    owner = pool.get
    stacked = pool.get
    pool.with_current_stack_locked_for_spec { stacked.put }
    replacement = pool.get
    replacement.value.should eq(3)
    replacement.put
    owner.put
    calls.should eq(3)
  end

  it "returns a cache after an exception in a scoped checkout" do
    calls = 0
    pool = Regex::Automata::Pool(Array(Char)).new do
      calls += 1
      ['a']
    end
    expect_raises(Exception, "consumer failed") do
      pool.with do |value|
        value << 'b'
        raise "consumer failed"
      end
    end
    pool.with { |value| value.should eq(['a', 'b']) }
    calls.should eq(1)
  end

  it "keeps the pool usable after the first factory raises" do
    calls = 0
    pool = Regex::Automata::Pool(Int32).new do
      calls += 1
      raise "first factory failed" if calls == 1
      calls
    end

    expect_raises(Exception, "first factory failed") { pool.get }
    guard = pool.get
    guard.value.should eq(2)
    guard.put
  end

  it "supports a nil cache value and a parallelism-sized shard pool" do
    calls = 0
    pool = Regex::Automata::Pool(Int32?).with_available_parallelism_capacity do
      calls += 1
      nil
    end
    pool.with { |value| value.should be_nil }
    pool.with { |value| value.should be_nil }
    calls.should eq(1)
  end

  it "reuses the Rust-style pool through Meta search consumers" do
    re = Regex::Automata::Meta::Regex.new("[a-z]+")
    first = re.pooled_cache_id_for_spec
    re.search(Regex::Automata::Input.new("abc")).should eq(Regex::Automata::Match.must(0, 0...3))
    re.is_match(Regex::Automata::Input.new("xyz")).should be_true
    re.search_half(Regex::Automata::Input.new("def")).should_not be_nil
    re.find_iter("abc def").count.should eq(2)
    re.captures_iter("abc def").count.should eq(2)
    re.pooled_cache_id_for_spec.should eq(first)
  end

  it "releases an early-stopped Meta iterator through close" do
    re = Regex::Automata::Meta::Regex.new("[a-z]+")
    first = re.pooled_cache_id_for_spec
    iter = re.find_iter("abc def")
    iter.next.should eq(Regex::Automata::Match.must(0, 0...3))
    iter.close
    re.pooled_cache_id_for_spec.should eq(first)
  end

  it "returns pooled Meta iterator caches on exception and limited split" do
    re = Regex::Automata::Meta::Regex.new("[a-z]+")
    first = re.pooled_cache_id_for_spec
    expect_raises(Exception, "consumer failed") do
      re.find_iter("abc def").each do
        raise "consumer failed"
      end
    end
    re.pooled_cache_id_for_spec.should eq(first)
    re.splitn(1, "abc def").to_a.should eq([Regex::Automata::Span.new(0, 7)])
    re.pooled_cache_id_for_spec.should eq(first)
  end

  it "does not acquire a Meta cache for impossible input" do
    re = Regex::Automata::Meta::Regex.new("^foo$")
    input = Regex::Automata::Input.new("xfoo").range(1...4)
    re.pool_unowned_for_spec?.should be_true
    re.search(input).should be_nil
    re.search_half(input).should be_nil
    re.is_match(input).should be_false
    re.search_slots(input, [] of Int32?).should be_nil
    caps = re.create_captures
    re.search_captures(input, caps)
    caps.is_match.should be_false
    re.which_overlapping_matches(input, Regex::Automata::PatternSet.new(1))
    re.pool_unowned_for_spec?.should be_true
  end
end
