require "./spec_helper"

describe Regex::Automata::Hybrid::Config do
  it "supports hybrid-specific defaults and quit panics" do
    config = Regex::Automata::Hybrid::Config.new

    config.get_cache_capacity.should eq(2 * (1 << 20))
    config.get_skip_cache_capacity_check.should be_false
    config.get_minimum_cache_clear_count.should be_nil
    config.get_minimum_bytes_per_state.should be_nil
    config.get_minimum_cache_capacity.should eq(1)

    expect_raises(Exception) do
      Regex::Automata::Hybrid::Config.new
        .unicode_word_boundary(true)
        .quit(0xFF_u8, false)
    end
  end
end

describe Regex::Automata::Hybrid::DFA do
  it "builds hybrid DFAs and exposes metadata" do
    dfa = Regex::Automata::Hybrid::DFA.new("foo[0-9]+")
    cache = dfa.create_cache

    dfa.pattern_len.should eq(1)
    dfa.memory_usage.should be > 0
    dfa.get_cache_capacity.should eq(2 * (1 << 20))
    dfa.get_byte_classes.alphabet_len.should be > 0
    dfa.universal_start_state(Regex::Automata::Anchored::No).should_not be_nil
    cache.memory_usage.should eq(0)
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

    state = Regex::Automata::OverlappingState.start
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
    dfa.try_search_overlapping_fwd(cache, ascii, Regex::Automata::OverlappingState.start).should eq(
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
    re.memory_usage.should be > 0
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
end
