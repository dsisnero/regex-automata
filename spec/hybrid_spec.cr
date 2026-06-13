require "./spec_helper"

describe Regex::Automata::Hybrid::LazyStateID do
  it "reports overflow with the vendored lazy-state-id error semantics" do
    err = Regex::Automata::Hybrid::LazyStateIDError
      .new((Regex::Automata::Hybrid::LazyStateID::MAX + 1).to_i64)

    err.attempted.should eq((Regex::Automata::Hybrid::LazyStateID::MAX + 1).to_i64)
    err.message.should eq(
      "failed to create LazyStateID from #{Regex::Automata::Hybrid::LazyStateID::MAX + 1}, which exceeds #{Regex::Automata::Hybrid::LazyStateID::MAX}"
    )
  end

  it "exposes tagged and untagged usize views" do
    sid = Regex::Automata::Hybrid::LazyStateID.new_unchecked(7)

    sid.as_usize_untagged.should eq(7)
    sid.to_match.as_usize_unchecked.should be > Regex::Automata::Hybrid::LazyStateID::MAX
    sid.to_match.as_usize_untagged.should eq(7)
  end
end

describe Regex::Automata::Hybrid::BuildError do
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
  end
end

describe Regex::Automata::Hybrid::StartError do
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
    ).compile_multi([hir])
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
end

describe Regex::Automata::Hybrid::Cache do
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
end

describe Regex::Automata::Hybrid::DFA do
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
    heuristic.get_config.get_quit(0x80_u8).should be_true
    heuristic.get_config.get_quit(0xFF_u8).should be_true

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
    state.get_match.should eq(Regex::Automata::HalfMatch.must(0, 6))

    patset = Regex::Automata::PatternSet.new(dfa.pattern_len)
    dfa.try_which_overlapping_matches(cache, Regex::Automata::Input.new("foo123"), patset).should be_nil
    patset.iter.to_a.should eq([Regex::Automata::PatternID.new(0)])
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
