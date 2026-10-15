require "./spec_helper"

# White-box access to Rust's private cache-clear path for accounting parity.
class Regex::Automata::Hybrid::Lazy
  def clear_for_spec : Nil
    clear_cache
  end

  def try_clear_for_spec
    try_clear_cache
  end

  def set_transition_for_spec(from : ::Regex::Automata::Hybrid::LazyStateID, to : ::Regex::Automata::Hybrid::LazyStateID) : Nil
    set_transition(from, ::Regex::Automata::Unit.u8('a'.ord.to_u8), to)
  end

  def set_start_state_for_spec(id : ::Regex::Automata::Hybrid::LazyStateID) : Nil
    set_start_state(::Regex::Automata::Anchored::No, ::Regex::Automata::Start::Text, nil, id)
  end

  def save_state_for_spec(id : ::Regex::Automata::Hybrid::LazyStateID) : Nil
    save_state(id)
  end

  def saved_state_id_for_spec : ::Regex::Automata::Hybrid::LazyStateID
    saved_state_id
  end
end

module Regex::Automata::Hybrid
  def self.clear_cache_for_spec(dfa : DFA, cache : Cache) : Nil
    Lazy.new(dfa, cache).clear_for_spec
  end

  def self.try_clear_cache_for_spec(dfa : DFA, cache : Cache)
    Lazy.new(dfa, cache).try_clear_for_spec
  end

  def self.lazy_for_spec(dfa : DFA, cache : Cache) : Lazy
    Lazy.new(dfa, cache)
  end
end

describe Regex::Automata::Hybrid::LazyStateID do
  it "exposes Rust's unsigned raw representation for every tag" do
    id = Regex::Automata::Hybrid::LazyStateID.new_unchecked(7)
    id.to_unknown.as_usize_unchecked.should eq((1_i64 << 31) | 7)
    Regex::Automata::Hybrid::LazyStateID.new_unchecked((1_i64 << 31) | 7).should eq(id.to_unknown)
    id.to_dead.as_usize_unchecked.should eq((1_i64 << 30) | 7)
    id.to_quit.as_usize_unchecked.should eq((1_i64 << 29) | 7)
    id.to_start.as_usize_unchecked.should eq((1_i64 << 28) | 7)
    id.to_match.as_usize_unchecked.should eq((1_i64 << 27) | 7)
  end

  it "reports overflow with the vendored lazy-state-id error semantics" do
    err = Regex::Automata::Hybrid::LazyStateIDError
      .new((Regex::Automata::Hybrid::LazyStateID::MAX + 1).to_i64)

    err.attempted.should eq((Regex::Automata::Hybrid::LazyStateID::MAX + 1).to_i64)
    err.message.should eq(
      "failed to create LazyStateID from #{Regex::Automata::Hybrid::LazyStateID::MAX + 1}, which exceeds #{Regex::Automata::Hybrid::LazyStateID::MAX}"
    )
  end

  it "reports the full unsigned usize value for an oversized state id" do
    result = Regex::Automata::Hybrid::LazyStateID.new(UInt64::MAX)
    result.should be_a(Regex::Automata::Hybrid::LazyStateIDError)
    error = result.as(Regex::Automata::Hybrid::LazyStateIDError)
    error.attempted.should eq(UInt64::MAX)
    error.message.should eq(
      "failed to create LazyStateID from #{UInt64::MAX}, which exceeds #{Regex::Automata::Hybrid::LazyStateID::MAX}"
    )
  end

  it "exposes tagged and untagged usize views" do
    sid = Regex::Automata::Hybrid::LazyStateID.new_unchecked(7)

    sid.as_usize_untagged.should eq(7)
    sid.to_match.as_usize_unchecked.should be > Regex::Automata::Hybrid::LazyStateID::MAX
    sid.to_match.as_usize_untagged.should eq(7)
  end

  it "preserves every Rust lazy-state tag independently" do
    sid = Regex::Automata::Hybrid::LazyStateID.new_unchecked(7)

    {
      sid.to_unknown => ->(value : Regex::Automata::Hybrid::LazyStateID) { value.is_unknown },
      sid.to_dead    => ->(value : Regex::Automata::Hybrid::LazyStateID) { value.is_dead },
      sid.to_quit    => ->(value : Regex::Automata::Hybrid::LazyStateID) { value.is_quit },
      sid.to_start   => ->(value : Regex::Automata::Hybrid::LazyStateID) { value.is_start },
      sid.to_match   => ->(value : Regex::Automata::Hybrid::LazyStateID) { value.is_match },
    }.each do |tagged, predicate|
      tagged.is_tagged.should be_true
      predicate.call(tagged).should be_true
      tagged.as_usize_untagged.should eq(7)
    end

    sid.is_tagged.should be_false
  end
end

describe Regex::Automata::Hybrid::BuildError do
  it "wraps pattern syntax failures through the Thompson NFA error" do
    err = expect_raises(Regex::Automata::Hybrid::BuildError, "error building NFA") do
      Regex::Automata::Hybrid::DFA.new("(")
    end

    nfa_error = err.source
    nfa_error.should be_a(Regex::Automata::NFA::BuildError)
    nfa_error = nfa_error.as(Regex::Automata::NFA::BuildError)
    nfa_error.kind.should eq(
      Regex::Automata::NFA::BuildError::Kind::Syntax
    )
    nfa_error.source.should_not be_nil
  end

  it "uses the vendored lazy-state-id-capacity error message" do
    inner = Regex::Automata::Hybrid::LazyStateIDError.new(
      (Regex::Automata::Hybrid::LazyStateID::MAX + 1).to_i64
    )
    err = Regex::Automata::Hybrid::BuildError.insufficient_state_id_capacity(inner)

    err.message.should eq(inner.message)
  end

  it "normalizes underlying nfa build failures to the hybrid build-error contract" do
    err = expect_raises(Regex::Automata::Hybrid::BuildError, "error building NFA") do
      Regex::Automata::Hybrid::Builder.new
        .thompson(Regex::Automata::NFA::NFA.config.nfa_size_limit(0))
        .build("[a-z]+")
    end

    err.is_size_limit_exceeded.should be_true
    err.size_limit.should eq(0_i64)
    err.source.should be_a(Regex::Automata::NFA::BuildError)
  end
end

describe Regex::Automata::Hybrid::StartError do
  it "formats quit look-behind bytes with Rust's DebugByte representation" do
    Regex::Automata::Hybrid::StartError.quit(' '.ord.to_u8).message.should eq(
      "error computing start state because the look-behind byte ' ' triggered a quit state"
    )
    Regex::Automata::Hybrid::StartError.quit(0xFF_u8).message.should eq(
      "error computing start state because the look-behind byte \\xFF triggered a quit state"
    )
  end

  it "includes the specific pattern id in unsupported-anchored messages" do
    err = Regex::Automata::Hybrid::StartError
      .unsupported_anchored(
        Regex::Automata::Anchored::Pattern,
        Regex::Automata::PatternID.new(3)
      )

    err.message.should eq(
      "error computing start state because anchored searches for a specific pattern (3) are not supported or enabled"
    )
  end

  it "retains the cache cause for start-state failures" do
    cause = Regex::Automata::Hybrid::CacheError.bad_efficiency
    err = Regex::Automata::Hybrid::StartError.cache(cause)

    err.cache?.should be_true
    err.source.should be(cause)
  end
end

describe Regex::Automata::Hybrid::Config do
  it "supports hybrid-specific defaults and quit panics" do
    config = Regex::Automata::Hybrid::Config.new

    config.get_cache_capacity.should eq(2 * (1 << 20))
    config.get_skip_cache_capacity_check.should be_false
    config.get_minimum_cache_clear_count.should be_nil
    config.get_minimum_bytes_per_state.should be_nil

    expect_raises(Exception) do
      Regex::Automata::Hybrid::Config.new
        .unicode_word_boundary(true)
        .quit(0xFF_u8, false)
    end
  end

  it "computes minimum cache capacity from the vendored nfa inputs" do
    syntax = Regex::Automata::Syntax::Config.new
    hir = Regex::Automata::Syntax.parse_with("[a-z]+", syntax)
    nfa = Regex::Automata::HirCompiler.new(
      Regex::Automata::NFA::NFA.config.captures(false),
      syntax
    ).build_many_from_hir([hir])
    config = Regex::Automata::Hybrid::Config.new
    min_cache = config.get_minimum_cache_capacity(nfa)

    min_cache.should be > 0

    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .cache_capacity(0)
          .skip_cache_capacity_check(true)
      )
      .build("[a-z]+")
    dfa.get_cache_capacity.should eq(min_cache)

    expect_raises(
      Regex::Automata::Hybrid::BuildError,
      "given cache capacity (0) is smaller than minimum required (#{min_cache})"
    ) do
      Regex::Automata::Hybrid::Builder.new
        .configure(Regex::Automata::Hybrid::DFA.config.cache_capacity(0))
        .build("[a-z]+")
    end
  end

  it "keeps disjoint quit-byte ranges as distinct contiguous byte classes" do
    syntax = Regex::Automata::Syntax::Config.new
    hir = Regex::Automata::Syntax.parse_with("a", syntax)
    nfa = Regex::Automata::HirCompiler.new(
      Regex::Automata::NFA::NFA.config.captures(false),
      syntax
    ).build_many_from_hir([hir])
    config = Regex::Automata::Hybrid::DFA.config
      .quit(0x01_u8, true)
      .quit(0x03_u8, true)
    quit = config.quit_set_from_nfa(nfa)
    classes = config.byte_classes_from_nfa(nfa, quit)

    # Rust ByteClassSet::add_set adds boundaries around each quit range.
    (0..3).each { |byte| classes[byte].should be < classes[byte + 1] }
    classes[0].should eq(0)
    classes[1].should eq(1)
    classes[2].should eq(2)
    classes[3].should eq(3)
    classes[4].should eq(4)

    base_minimum = Regex::Automata::Hybrid::DFA.config.get_minimum_cache_capacity(nfa)
    split_minimum = config.get_minimum_cache_capacity(nfa)
    split_minimum.should be > base_minimum

    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(config.cache_capacity(0).skip_cache_capacity_check(true))
      .build_from_nfa(nfa)
    dfa.get_cache_capacity.should eq(split_minimum)
    dfa.get_byte_classes.to_bytes.should eq(classes.to_bytes)

    cache = dfa.create_cache
    dfa.try_search_fwd(cache, Regex::Automata::Input.new(Bytes[0x02_u8, 0x61_u8])).should eq(
      Regex::Automata::HalfMatch.must(0, 2)
    )
    dfa.try_search_fwd(cache, Regex::Automata::Input.new(Bytes[0x01_u8, 0x61_u8])).should eq(
      Regex::Automata::MatchError.quit(0x01_u8, 0)
    )
  end
end

describe Regex::Automata::Hybrid::Cache do
  it "accounts for aggregate cache bytes beyond Int32 without allocating them" do
    cache = Regex::Automata::Hybrid::DFA.new("a").create_cache
    cache.memory_usage_state = Int32::MAX.to_u64

    cache.memory_usage.should be > Int32::MAX.to_u64
  end

  it "counts retained stack allocation after clearing and resetting" do
    dfa = Regex::Automata::Hybrid::DFA.new("[ab]+")
    cache = dfa.create_cache
    initial = cache.memory_usage
    100.times { cache.stack << Regex::Automata::StateID.must(0) }
    allocated = cache.stack.@capacity * Regex::Automata::StateID::SIZE
    cache.memory_usage.should eq(initial + allocated)

    Regex::Automata::Hybrid.clear_cache_for_spec(dfa, cache)
    cache.stack.clear
    cache.memory_usage.should eq(initial + allocated)
    cache.reset(dfa)
    cache.clear_count.should eq(0)
    cache.memory_usage.should eq(initial + allocated)
  end

  it "reuses sparse-set buffers when resetting against the same DFA" do
    dfa = Regex::Automata::Hybrid::DFA.new("[ab]+")
    cache = dfa.create_cache
    dense = cache.sparses.set1.@dense.to_unsafe
    sparse = cache.sparses.set1.@sparse.to_unsafe
    cache.reset(dfa)
    cache.sparses.set1.@dense.to_unsafe.should eq(dense)
    cache.sparses.set1.@sparse.to_unsafe.should eq(sparse)
  end

  it "retargets a cache to a different DFA and clears prior progress" do
    first = Regex::Automata::Hybrid::DFA.new("\\w")
    second = Regex::Automata::Hybrid::DFA.new("\\W")
    cache = first.create_cache
    first.try_search_fwd(cache, Regex::Automata::Input.new("Δ")).should eq(
      Regex::Automata::HalfMatch.must(0, 2)
    )
    cache.search_start(10)
    cache.search_update(15)

    cache.reset(second)
    cache.clear_count.should eq(0)
    cache.search_total_len.should eq(0)
    cache.sparses.set1.capacity.should eq(second.get_nfa.states.size)
    second.try_search_fwd(cache, Regex::Automata::Input.new("☃")).should eq(
      Regex::Automata::HalfMatch.must(0, 3)
    )
  end

  it "checks clear limits before mutating the cache and accepts efficient progress" do
    config = Regex::Automata::Hybrid::DFA.config
      .minimum_cache_clear_count(0)
      .minimum_bytes_per_state(10)
    dfa = Regex::Automata::Hybrid::Builder.new.configure(config).build("[ab]+")
    cache = dfa.create_cache
    initial = cache.memory_usage
    error = Regex::Automata::Hybrid.try_clear_cache_for_spec(dfa, cache)
    error.should be_a(Regex::Automata::Hybrid::CacheError)
    error.as(Regex::Automata::Hybrid::CacheError).message.should eq(
      Regex::Automata::Hybrid::CacheError.bad_efficiency.message
    )
    cache.clear_count.should eq(0)
    cache.memory_usage.should eq(initial)

    cache.search_start(0)
    cache.search_update(100)
    Regex::Automata::Hybrid.try_clear_cache_for_spec(dfa, cache).should be_nil
    cache.clear_count.should eq(1)
    cache.search_total_len.should eq(0)
  end

  it "saturates the efficiency threshold instead of overflowing" do
    config = Regex::Automata::Hybrid::DFA.config
      .minimum_cache_clear_count(0)
      .minimum_bytes_per_state(UInt64::MAX)
    dfa = Regex::Automata::Hybrid::Builder.new.configure(config).build("a")
    cache = dfa.create_cache
    cache.search_start(0)
    cache.search_update(1)
    Regex::Automata::Hybrid.try_clear_cache_for_spec(dfa, cache).should be_a(
      Regex::Automata::Hybrid::CacheError
    )
    cache.clear_count.should eq(0)
  end

  it "compares a usize-width cache clear count without narrowing" do
    threshold = Int32::MAX.to_u64 + 1_u64
    config = Regex::Automata::Hybrid::DFA.config.minimum_cache_clear_count(threshold)
    dfa = Regex::Automata::Hybrid::Builder.new.configure(config).build("a")
    cache = dfa.create_cache
    cache.clear_count = threshold

    Regex::Automata::Hybrid.try_clear_cache_for_spec(dfa, cache).should be_a(
      Regex::Automata::Hybrid::CacheError
    )
    cache.clear_count.should eq(threshold)
  end

  it "keeps only post-clear progress when measuring cache efficiency" do
    dfa = Regex::Automata::Hybrid::DFA.new("[ab]+")
    cache = dfa.create_cache
    cache.search_start(10)
    cache.search_update(17)

    # Rust's clear_cache advances progress.start to progress.at. Exercise the
    # cold path directly so this checks accounting independently of search.
    Regex::Automata::Hybrid.clear_cache_for_spec(dfa, cache)
    cache.clear_count.should eq(1)
    cache.search_total_len.should eq(0)
    cache.search_update(20)
    cache.search_total_len.should eq(3)
    cache.search_finish(22)
    cache.search_total_len.should eq(5)
  end

  it "preserves a tagged start state when a cold clear remaps its ID" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.specialize_start_states(true))
      .build("a+")
    cache = dfa.create_cache
    input = Regex::Automata::Input.new("aaa")
    start = dfa.start_state_forward(cache, input).as(Regex::Automata::Hybrid::LazyStateID)
    start.is_start.should be_true
    before = cache.states[start.as_usize_untagged >> dfa.stride2].to_slice.dup
    lazy = Regex::Automata::Hybrid.lazy_for_spec(dfa, cache)

    lazy.save_state_for_spec(start)
    lazy.clear_for_spec
    restored = lazy.saved_state_id_for_spec
    restored.is_start.should be_true
    cache.states[restored.as_usize_untagged >> dfa.stride2].to_slice.should eq(before)
    dfa.next_state(cache, restored, 'a'.ord.to_u8).should be_a(Regex::Automata::Hybrid::LazyStateID)
  end

  it "searches normally with a skipped undersized requested capacity until the cache actually fills" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .cache_capacity(0)
          .skip_cache_capacity_check(true)
          .minimum_cache_clear_count(0)
      )
      .build("a")
    cache = dfa.create_cache
    dfa.try_search_fwd(cache, Regex::Automata::Input.new("a")).should eq(
      Regex::Automata::HalfMatch.must(0, 1)
    )
  end

  it "tracks reverse search progress by absolute distance" do
    dfa = Regex::Automata::Hybrid::DFA.new("[0-9]+")
    cache = dfa.create_cache

    cache.search_start(10)
    cache.search_update(7)
    cache.search_finish(4)

    cache.search_total_len.should eq(6)
  end

  it "finishes an unfinished prior search when a new one starts" do
    dfa = Regex::Automata::Hybrid::DFA.new("[0-9]+")
    cache = dfa.create_cache

    cache.search_start(10)
    cache.search_update(7)
    cache.search_start(5)
    cache.search_finish(2)

    cache.search_total_len.should eq(6)
  end

  it "accumulates repeated search distances beyond a single Int32 range" do
    dfa = Regex::Automata::Hybrid::DFA.new("a")
    cache = dfa.create_cache
    2.times do
      cache.search_start(0)
      cache.search_finish(Int32::MAX)
    end
    cache.search_total_len.should eq(Int32::MAX.to_i64 * 2)
  end

  it "tracks Rust usize-width forward, reverse, and cumulative progress" do
    cache = Regex::Automata::Hybrid::DFA.new("a").create_cache
    beyond_i64 = Int64::MAX.to_u64 + 1_u64

    cache.search_start(0_u64)
    cache.search_update(beyond_i64)
    cache.search_total_len.should eq(beyond_i64)
    cache.search_finish(beyond_i64)

    cache.search_start(beyond_i64)
    cache.search_finish(beyond_i64 - 2_u64)
    cache.search_total_len.should eq(beyond_i64 + 2_u64)
  end

  it "uses full-width progress when deciding whether a cache clear is efficient" do
    threshold = Int64::MAX.to_u64 + 1_u64
    config = Regex::Automata::Hybrid::DFA.config
      .minimum_cache_clear_count(0)
      .minimum_bytes_per_state(threshold // 4_u64)
    dfa = Regex::Automata::Hybrid::Builder.new.configure(config).build("a")
    cache = dfa.create_cache
    cache.search_start(0_u64)
    cache.search_update(threshold)

    Regex::Automata::Hybrid.try_clear_cache_for_spec(dfa, cache).should be_nil
    cache.clear_count.should eq(1_u64)
    cache.search_total_len.should eq(0_u64)
  end

  it "requires an active search before progress updates or completion" do
    cache = Regex::Automata::Hybrid::DFA.new("a").create_cache
    expect_raises(Exception, "no in-progress search to update") { cache.search_update(1) }
    expect_raises(Exception, "no in-progress search to finish") { cache.search_finish(1) }
    cache.search_total_len.should eq(0_u64)
  end
end

describe "hybrid tagged transitions and start maps" do
  it "finds delayed matches through the direct byte and EOI transition API" do
    dfa = Regex::Automata::Hybrid::DFA.new_many(["[a-z]+r", "[0-9]{4}"])
    cache = dfa.create_cache
    input = Regex::Automata::Input.new("bar")
    id = dfa.start_state_forward(cache, input).as(Regex::Automata::Hybrid::LazyStateID)
    "bar".to_slice.each do |byte|
      id = dfa.next_state(cache, id, byte).as(Regex::Automata::Hybrid::LazyStateID)
    end
    id.is_match.should be_false
    id = dfa.next_eoi_state(cache, id).as(Regex::Automata::Hybrid::LazyStateID)
    id.is_match.should be_true
    dfa.match_len(cache, id).should eq(1)
    dfa.match_pattern(cache, id, 0).should eq(Regex::Automata::PatternID.new(0))
  end

  it "keeps untagged transition lookup read-only and preserves cached tags" do
    dfa = Regex::Automata::Hybrid::DFA.new("a")
    cache = dfa.create_cache
    start = dfa.start_state_forward(cache, Regex::Automata::Input.new("a")).as(Regex::Automata::Hybrid::LazyStateID)
    start.is_tagged.should be_false
    states_before = cache.states.size
    transitions_before = cache.trans.size

    missing = dfa.next_state_untagged(cache, start, 'a'.ord.to_u8).as(Regex::Automata::Hybrid::LazyStateID)
    missing.is_unknown.should be_true
    dfa.next_state_untagged_unchecked(cache, start, 'a'.ord.to_u8).should eq(missing)
    cache.states.size.should eq(states_before)
    cache.trans.size.should eq(transitions_before)

    computed = dfa.next_state(cache, start, 'a'.ord.to_u8).as(Regex::Automata::Hybrid::LazyStateID)
    computed.is_unknown.should be_false
    dfa.next_state_untagged(cache, start, 'a'.ord.to_u8).should eq(computed)
    dfa.next_state_untagged_unchecked(cache, start, 'a'.ord.to_u8).should eq(computed)

    match = dfa.next_state(cache, computed, 'z'.ord.to_u8).as(Regex::Automata::Hybrid::LazyStateID)
    match.is_match.should be_true
    dfa.next_state_untagged(cache, computed, 'z'.ord.to_u8).should eq(match)
    dfa.next_state_untagged_unchecked(cache, computed, 'z'.ord.to_u8).should eq(match)
  end

  it "loops every sentinel row and initializes pattern-start slots lazily" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.starts_for_each_pattern(true))
      .build_many(["a", "b"])
    cache = dfa.create_cache
    stride = dfa.stride
    unknown = Regex::Automata::Hybrid::LazyStateID.new_unchecked(0).to_unknown
    dead = Regex::Automata::Hybrid::LazyStateID.new_unchecked(stride).to_dead
    quit = Regex::Automata::Hybrid::LazyStateID.new_unchecked(2 * stride).to_quit
    {unknown, dead, quit}.each_with_index do |id, row|
      dfa.get_byte_classes.representatives.each do |unit|
        column = dfa.get_byte_classes.get_by_unit(unit)
        cache.trans[row * stride + column].should eq(id)
      end
    end

    group_len = Regex::Automata::Start.len
    cache.starts.size.should eq(group_len * 4)
    cache.starts.each { |id| id.should eq(unknown) }
    input = Regex::Automata::Input.new("a")
      .anchored_pattern(Regex::Automata::PatternID.new(0))
    first = dfa.start_state_forward(cache, input).as(Regex::Automata::Hybrid::LazyStateID)
    slot = (2 * group_len) + Regex::Automata::Start::Text.as_usize
    cache.starts[slot].should eq(first)
    count = cache.states.size
    dfa.start_state_forward(cache, input).should eq(first)
    cache.states.size.should eq(count)
    cache.starts[slot + group_len].should eq(unknown)
  end

  it "caches all six look-behind start categories in their Rust slots" do
    term = 0_u8
    dfa = Regex::Automata::Hybrid::Builder.new
      .syntax(Regex::Automata::Syntax::Config.new.line_terminator(term))
      .thompson(Regex::Automata::NFA::NFA.config.look_matcher(Regex::Automata::LookMatcher.new(term)))
      .build("(?m)^a")
    cache = dfa.create_cache
    unknown = Regex::Automata::Hybrid::LazyStateID.new_unchecked(0).to_unknown
    bytes = {
      {Regex::Automata::Start::NonWordByte, ' '.ord.to_u8},
      {Regex::Automata::Start::WordByte, 'b'.ord.to_u8},
      {Regex::Automata::Start::LineLF, '\n'.ord.to_u8},
      {Regex::Automata::Start::LineCR, '\r'.ord.to_u8},
      {Regex::Automata::Start::CustomLineTerminator, term},
    }
    text = dfa.start_state(cache, Regex::Automata::Input.new("a"))
    text.should be_a(Regex::Automata::Hybrid::LazyStateID)
    cache.starts[Regex::Automata::Start::Text.as_usize].should eq(text)
    bytes.each do |kind, preceding|
      slot = kind.as_usize
      cache.starts[slot].should eq(unknown)
      input = Regex::Automata::Input.new(Bytes[preceding, 'a'.ord.to_u8]).span(1...2)
      id = dfa.start_state(cache, input)
      id.should be_a(Regex::Automata::Hybrid::LazyStateID)
      cache.starts[slot].should eq(id)
    end
  end

  it "rejects invalid state IDs in cold transition and start-map writes" do
    dfa = Regex::Automata::Hybrid::DFA.new("a")
    cache = dfa.create_cache
    lazy = Regex::Automata::Hybrid.lazy_for_spec(dfa, cache)
    invalid = Regex::Automata::Hybrid::LazyStateID.new_unchecked(cache.trans.size + dfa.stride)
    valid = Regex::Automata::Hybrid::LazyStateID.new_unchecked(0).to_unknown
    expect_raises(Exception) { lazy.set_transition_for_spec(valid, invalid) }
    expect_raises(Exception) { lazy.set_start_state_for_spec(invalid) }
  end
end

describe Regex::Automata::Hybrid::DFA do
  it "reports a forward start quit at the look-behind offset" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.quit('x'.ord.to_u8, true))
      .build("a")
    cache = dfa.create_cache
    input = Regex::Automata::Input.new("xa").span(1...2)

    dfa.start_state(cache, input).should be_a(Regex::Automata::Hybrid::StartError)
    dfa.start_state_forward(cache, input).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 0)
    )
    dfa.try_search_fwd(cache, input).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 0)
    )

    # Rust checks the look-behind quit byte before unsupported anchoring.
    anchored = input.clone.anchored_pattern(Regex::Automata::PatternID.new(0))
    dfa.start_state_forward(cache, anchored).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 0)
    )
  end

  it "reports a reverse start quit at the look-ahead offset" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.quit('x'.ord.to_u8, true))
      .thompson(Regex::Automata::NFA::NFA.config.reverse(true))
      .build("a")
    cache = dfa.create_cache
    input = Regex::Automata::Input.new("ax").span(0...1)

    dfa.start_state_reverse(cache, input).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 1)
    )
    dfa.try_search_rev(cache, input).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 1)
    )
  end

  it "rejects Unicode word boundaries unless heuristic support or a full non-ASCII quitset is enabled" do
    expect_raises(
      Regex::Automata::Hybrid::BuildError,
      "unsupported regex feature for DFAs: cannot build lazy DFAs for regexes with Unicode word boundaries; switch to ASCII word boundaries, or heuristically enable Unicode word boundaries or use a different regex engine"
    ) do
      Regex::Automata::Hybrid::DFA.new("\\b")
    end

    heuristic = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.unicode_word_boundary(true))
      .build("\\b")
    heuristic.get_config.get_quit(0x80_u8).should be_false
    heuristic.get_config.get_quit(0xFF_u8).should be_false
    heuristic.get_quitset.contains(0x80_u8).should be_true
    heuristic.get_quitset.contains(0xFF_u8).should be_true

    quit_config = Regex::Automata::Hybrid::DFA.config
    (0x80..0xFF).each do |byte|
      quit_config.quit(byte.to_u8, true)
    end
    Regex::Automata::Hybrid::Builder.new.configure(quit_config).build("\\b")
  end

  it "builds hybrid DFAs and exposes metadata" do
    dfa = Regex::Automata::Hybrid::DFA.new("foo[0-9]+")
    cache = dfa.create_cache

    dfa.pattern_len.should eq(1)
    dfa.memory_usage.should eq(0)
    dfa.get_cache_capacity.should eq(2 * (1 << 20))
    dfa.get_byte_classes.alphabet_len.should be > 0
    dfa.universal_start_state(Regex::Automata::Anchored::No).should_not be_nil
    cache.memory_usage.should be > 0
    cache.clear_count.should eq(0)
  end

  it "preserves the active lazy state across constrained-cache clears" do
    pattern = "[ab]{20}"
    seed = Regex::Automata::Hybrid::DFA.new(pattern)
    capacity = Regex::Automata::Hybrid::DFA.config.get_minimum_cache_capacity(seed.get_nfa)
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.cache_capacity(capacity))
      .build(pattern)
    cache = dfa.create_cache

    dfa.try_search_fwd(cache, Regex::Automata::Input.new("a" * 20)).should eq(
      Regex::Automata::HalfMatch.must(0, 20)
    )
    cache.clear_count.should be > 0
  end

  it "merges repeated builder configuration calls with vendored overwrite semantics" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo"]
    ).not_nil!
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.prefilter(pre))
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .specialize_start_states(true)
          .quit('x'.ord.to_u8, true)
      )
      .build("foo[0-9]+")

    dfa.get_prefilter.should eq(pre)
    dfa.get_config.get_specialize_start_states.should be_true
    dfa.get_config.get_quit('x'.ord.to_u8).should be_true
  end

  it "supports default, no-byte-classes, shrink, and starts-for-each-pattern workflows" do
    default_dfa = Regex::Automata::Hybrid::DFA.new_many(["[0-9]+", "[a-z]+"])
    cache = default_dfa.create_cache
    default_dfa.try_search_fwd(cache, Regex::Automata::Input.new("foo12345bar")).should eq(
      Regex::Automata::HalfMatch.must(1, 3)
    )

    no_classes = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.byte_classes(false))
      .build("[a-z]+")
    no_classes.get_byte_classes.is_singleton.should be_true

    shrink = Regex::Automata::Hybrid::Builder.new
      .thompson(Regex::Automata::NFA::NFA.config.shrink(true))
      .build("[a-z]+")
    cache = shrink.create_cache
    shrink.try_search_fwd(cache, Regex::Automata::Input.new("abc123")).should eq(
      Regex::Automata::HalfMatch.must(0, 3)
    )

    starts = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.starts_for_each_pattern(true))
      .build_many(["[a-z]+", "[0-9]+"])
    cache = starts.create_cache
    input = Regex::Automata::Input.new("123abc")
      .anchored(Regex::Automata::Anchored::Pattern, Regex::Automata::PatternID.new(0))
    starts.try_search_fwd(cache, input).should be_nil
  end

  it "supports prefilters, overlapping queries, and start state tagging" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo", "bar"]
    ).not_nil!
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .prefilter(pre)
          .specialize_start_states(true)
      )
      .build_many(["foo[0-9]+", "bar[0-9]+"])
    cache = dfa.create_cache

    dfa.get_prefilter.should eq(pre)
    start = dfa.start_state_forward(cache, Regex::Automata::Input.new("foo123"))
    start.should be_a(Regex::Automata::Hybrid::LazyStateID)
    start.as(Regex::Automata::Hybrid::LazyStateID).is_start.should be_true

    state = Regex::Automata::Hybrid::OverlappingState.start
    dfa.try_search_overlapping_fwd(
      cache,
      Regex::Automata::Input.new("foo123"),
      state
    ).should be_nil
    # Rust overlapping search reports the first end offset, even with
    # leftmost-first match kind; subsequent calls report longer endings.
    state.get_match.should eq(Regex::Automata::HalfMatch.must(0, 4))

    patset = Regex::Automata::PatternSet.new(dfa.pattern_len)
    dfa.try_which_overlapping_matches(cache, Regex::Automata::Input.new("foo123"), patset).should be_nil
    patset.iter.to_a.should eq([Regex::Automata::PatternID.new(0)])
  end

  it "preserves a pending leftmost match when a prefilter reaches a tagged start state" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["ab", "c"]
    ).not_nil!
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .prefilter(prefilter)
          .starts_for_each_pattern(true)
      )
      .build("(?:ab|c)*c")
    cache = dfa.create_cache
    haystack = "cabac"
    expected = Regex::Automata::HalfMatch.must(0, 1)

    # This pre-populates the anchored start state so the later equivalent
    # state is tagged, matching the vendor regression's cache setup.
    dfa.try_search_fwd(
      cache,
      Regex::Automata::Input.new(haystack).anchored(Regex::Automata::Anchored::Yes)
    ).should eq(expected)
    dfa.try_search_fwd(cache, Regex::Automata::Input.new(haystack)).should eq(expected)
  end

  it "restarts prefiltered searches with bounded look-around context" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["abc"]
    ).not_nil!
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .prefilter(prefilter)
          .specialize_start_states(true)
      )
      .build("(?-u:\\b)abc")
    cache = dfa.create_cache
    input = Regex::Automata::Input.new("xabc ").span(1...4)

    dfa.try_search_fwd(cache, input).should be_nil
  end

  it "restarts all-matches overlap searches at prefilter candidates" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["abc"]
    ).not_nil!
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .prefilter(prefilter)
          .match_kind(Regex::Automata::MatchKind::All)
          .specialize_start_states(true)
      )
      .build("(?-u:\\b)abc")
    cache = dfa.create_cache
    state = Regex::Automata::Hybrid::OverlappingState.start
    input = Regex::Automata::Input.new("xabc ").span(1...4)

    dfa.try_search_overlapping_fwd(cache, input, state).should be_nil
    state.get_match.should be_nil
  end

  it "supports quit bytes and implicit unicode word boundary enabling" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.quit('x'.ord.to_u8, true))
      .build("[[:word:]]+$")
    cache = dfa.create_cache

    dfa.try_search_fwd(cache, Regex::Automata::Input.new("abcxyz")).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 3)
    )
    dfa.try_search_overlapping_fwd(
      cache,
      Regex::Automata::Input.new("abcxyz"),
      Regex::Automata::Hybrid::OverlappingState.start
    ).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 3)
    )

    rev = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.quit('x'.ord.to_u8, true))
      .thompson(Regex::Automata::NFA::NFA.config.reverse(true))
      .build("^[[:word:]]+")
    cache = rev.create_cache
    rev.try_search_rev(cache, Regex::Automata::Input.new("abcxyz")).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 3)
    )

    config = Regex::Automata::Hybrid::DFA.config
    (0x80..0xFF).each do |byte|
      config.quit(byte.to_u8, true)
    end
    implicit = Regex::Automata::Hybrid::Builder.new.configure(config).build("\\b")
    cache = implicit.create_cache
    implicit.try_search_fwd(cache, Regex::Automata::Input.new(" a")).should eq(
      Regex::Automata::HalfMatch.must(0, 1)
    )
  end

  it "handles heuristic unicode word boundaries for reverse contextual searches" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.unicode_word_boundary(true))
      .thompson(Regex::Automata::NFA::NFA.config.reverse(true))
      .build("\\b[0-9]+\\b")
    cache = dfa.create_cache

    dfa.try_search_rev(
      cache,
      Regex::Automata::Input.new("β123").span(2...5)
    ).should eq(Regex::Automata::MatchError.quit(0xB2_u8, 1))

    dfa.try_search_rev(
      cache,
      Regex::Automata::Input.new("123β").span(0...3)
    ).should eq(Regex::Automata::MatchError.quit(0xCE_u8, 3))
  end

  it "gives up for undersized lazy caches with the tracked api offsets" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .skip_cache_capacity_check(true)
          .cache_capacity(0)
          .minimum_cache_clear_count(0)
      )
      .build("[aβ]{99}")
    cache = dfa.create_cache

    ascii = Regex::Automata::Input.new("a" * 101)
    dfa.try_search_fwd(cache, ascii).should eq(Regex::Automata::MatchError.gave_up(24))
    dfa.try_search_overlapping_fwd(cache, ascii, Regex::Automata::Hybrid::OverlappingState.start).should eq(
      Regex::Automata::MatchError.gave_up(24)
    )

    beta = Regex::Automata::Input.new("β" * 101)
    dfa.try_search_fwd(cache, beta).should eq(Regex::Automata::MatchError.gave_up(2))

    cache.reset(dfa)
    dfa.try_search_fwd(cache, beta).should eq(Regex::Automata::MatchError.gave_up(26))
    dfa.try_search_fwd(cache, ascii).should eq(Regex::Automata::MatchError.gave_up(13))
  end

  it "rejects undersized cache capacity unless the skip check is enabled" do
    expect_raises(Regex::Automata::Hybrid::BuildError) do
      Regex::Automata::Hybrid::Builder.new
        .configure(Regex::Automata::Hybrid::DFA.config.cache_capacity(0))
        .build("abc")
    end

    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .cache_capacity(0)
          .skip_cache_capacity_check(true)
      )
      .build("abc")
    cache = dfa.create_cache
    dfa.try_search_fwd(cache, Regex::Automata::Input.new("abc")).should eq(
      Regex::Automata::HalfMatch.must(0, 3)
    )
  end

  it "preserves anchored-pattern ids in unsupported hybrid errors" do
    dfa = Regex::Automata::Hybrid::DFA.new_many(["[a-z]+", "[0-9]+"])
    cache = dfa.create_cache
    err = dfa.try_search_fwd(
      cache,
      Regex::Automata::Input.new("123").anchored_pattern(Regex::Automata::PatternID.new(1))
    )

    err.should be_a(Regex::Automata::MatchError)
    err = err.as(Regex::Automata::MatchError)
    err.unsupported_anchored?.should be_true
    err.pattern.should eq(Regex::Automata::PatternID.new(1))
    err.message.should eq(
      "anchored searches for a specific pattern (1) are not supported or enabled"
    )
  end
end

describe Regex::Automata::Hybrid::Regex do
  it "builds regex wrappers and supports match iteration" do
    re = Regex::Automata::Hybrid::Regex.new_many(["[a-z]+", "[0-9]+"])
    cache = re.create_cache

    re.is_match(cache, Regex::Automata::Input.new("abc").earliest(true)).should be_true
    re.find(cache, "abc 1 foo 4567 0 quux").should eq(
      Regex::Automata::Match.must(0, 0...3)
    )
    re.find_iter(cache, "abc 1 foo 4567 0 quux").to_a.should eq([
      Regex::Automata::Match.must(0, 0...3),
      Regex::Automata::Match.must(1, 4...5),
      Regex::Automata::Match.must(0, 6...9),
      Regex::Automata::Match.must(1, 10...14),
      Regex::Automata::Match.must(1, 15...16),
      Regex::Automata::Match.must(0, 17...21),
    ])
  end

  it "supports regex builder options, cache parts, and reset" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo"]
    ).not_nil!
    re = Regex::Automata::Hybrid::Regex.builder
      .dfa(
        Regex::Automata::Hybrid::DFA.config
          .prefilter(pre)
          .starts_for_each_pattern(true)
      )
      .thompson(Regex::Automata::NFA::NFA.config.shrink(true))
      .build_many(["foo[0-9]+", "bar[0-9]+"])
    cache = re.create_cache

    re.forward.get_prefilter.should eq(pre)
    re.pattern_len.should eq(2)
    re.memory_usage.should eq(0)
    cache.as_parts[0].should be_a(Regex::Automata::Hybrid::Cache)
    cache.as_parts_mut[1].should be_a(Regex::Automata::Hybrid::Cache)
    cache.memory_usage.should eq(cache.forward.memory_usage + cache.reverse.memory_usage)

    re.find(cache, "zzzfoo123zzz").should eq(
      Regex::Automata::Match.must(0, 3...9)
    )

    other = Regex::Automata::Hybrid::Regex.new("\\W")
    other.reset_cache(cache)
    other.find(cache, "!").should eq(
      Regex::Automata::Match.must(0, 0...1)
    )
  end

  it "builds the reverse regex dfa with only the vendored overrides" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo"]
    ).not_nil!
    re = Regex::Automata::Hybrid::Regex.builder
      .dfa(
        Regex::Automata::Hybrid::DFA.config
          .prefilter(pre)
          .specialize_start_states(true)
          .quit('x'.ord.to_u8, true)
      )
      .build("foo[0-9]+")

    re.forward.get_prefilter.should eq(pre)
    re.reverse.get_prefilter.should be_nil
    re.forward.get_config.get_specialize_start_states.should be_true
    re.reverse.get_config.get_specialize_start_states.should be_false
    re.forward.get_match_kind.should eq(Regex::Automata::MatchKind::LeftmostFirst)
    re.reverse.get_match_kind.should eq(Regex::Automata::MatchKind::All)
    re.forward.get_config.get_quit('x'.ord.to_u8).should be_true
    re.reverse.get_config.get_quit('x'.ord.to_u8).should be_true
    re.forward.get_config.get_starts_for_each_pattern.should be_false
    re.reverse.get_config.get_starts_for_each_pattern.should be_false
  end

  it "keeps caches uncleared with the tracked no-cache-clearing configuration" do
    re = Regex::Automata::Hybrid::Regex.builder
      .dfa(Regex::Automata::Hybrid::DFA.config.minimum_cache_clear_count(0))
      .build_many(["[a-z]+", "[0-9]+"])
    cache = re.create_cache

    re.find(cache, "abc 123").should eq(Regex::Automata::Match.must(0, 0...3))
    re.find_iter(cache, "abc 123").to_a.should eq([
      Regex::Automata::Match.must(0, 0...3),
      Regex::Automata::Match.must(1, 4...7),
    ])

    cache.forward.clear_count.should eq(0)
    cache.reverse.clear_count.should eq(0)
  end

  it "uses the vendored reverse-search setup for regex try_search" do
    re = Regex::Automata::Hybrid::Regex.new("a*ab")
    cache = re.create_cache

    re.try_search(
      cache,
      Regex::Automata::Input.new("aaab").earliest(true)
    ).should eq(Regex::Automata::Match.must(0, 0...4))
  end
end
