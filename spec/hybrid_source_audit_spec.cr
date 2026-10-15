require "./spec_helper"

describe "pinned Rust hybrid DFA API examples" do
  it "keeps requested quit settings separate from Unicode-derived quit bytes" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.unicode_word_boundary(true))
      .build("\\b")

    dfa.get_config.get_quit(0x80_u8).should be_false
    dfa.get_config.get_quit(0xFF_u8).should be_false
    dfa.get_quitset.contains(0x80_u8).should be_true
    dfa.get_quitset.contains(0xFF_u8).should be_true
  end

  it "overwrites the requested quit set independently of Unicode boundary support" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.unicode_word_boundary(true))
      .configure(Regex::Automata::Hybrid::DFA.config.quit('\n'.ord.to_u8, true))
      .build("\\b")

    dfa.get_config.get_unicode_word_boundary.should be_true
    dfa.get_config.get_quit('\n'.ord.to_u8).should be_true
    dfa.get_config.get_quit(0x80_u8).should be_false
    dfa.get_quitset.contains('\n'.ord.to_u8).should be_true
    dfa.get_quitset.contains(0x80_u8).should be_true
  end

  it "keeps the first automatic start-specialization choice when prefilter changes" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo"]
    ).not_nil!
    config = Regex::Automata::Hybrid::DFA.config
      .prefilter(prefilter)
      .prefilter(nil)

    config.get_specialize_start_states.should be_true
    dfa = Regex::Automata::Hybrid::Builder.new.configure(config).build("foo")
    dfa.get_config.get_prefilter.should be_nil
    dfa.get_config.get_specialize_start_states.should be_true
  end

  it "builds the Rust byte-oriented builder example with Unicode and UTF-8 disabled" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.cache_capacity(5_000))
      .thompson(Regex::Automata::NFA::NFA.config.utf8(false))
      .syntax(Regex::Automata::Syntax::Config.new.unicode(false).utf8(false))
      .build("foo[^b]ar.*")
    cache = dfa.create_cache
    haystack = Bytes[0xFE_u8, 0x66_u8, 0x6F_u8, 0x6F_u8, 0xFF_u8,
      0x61_u8, 0x72_u8, 0xE2_u8, 0x98_u8, 0xFF_u8, 0x0A_u8]

    dfa.try_search_fwd(cache, Regex::Automata::Input.new(haystack)).should eq(
      Regex::Automata::HalfMatch.must(0, 10)
    )
  end

  it "builds from a separately configured Thompson NFA" do
    nfa = Regex::Automata::HirCompiler.new
      .configure(Regex::Automata::NFA::NFA.config.shrink(true))
      .build("[0-9]+")
    dfa = Regex::Automata::Hybrid::Builder.new.build_from_nfa(nfa)

    dfa.try_search_fwd(dfa.create_cache, Regex::Automata::Input.new("foo123bar")).should eq(
      Regex::Automata::HalfMatch.must(0, 6)
    )
  end

  it "ports Rust's heuristic_unicode_reverse contextual-search regression" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.unicode_word_boundary(true))
      .thompson(Regex::Automata::NFA::NFA.config.reverse(true))
      .build("\\b[0-9]+\\b")
    cache = dfa.create_cache

    input = Regex::Automata::Input.new("β123").range(2...5)
    dfa.try_search_rev(cache, input).should eq(
      Regex::Automata::MatchError.quit(0xB2_u8, 1)
    )

    input = Regex::Automata::Input.new("123β").range(0...3)
    dfa.try_search_rev(cache, input).should eq(
      Regex::Automata::MatchError.quit(0xCE_u8, 3)
    )
  end

  it "merges repeated Thompson builder settings as Rust's Compiler::configure does" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .thompson(Regex::Automata::NFA::NFA.config.reverse(true))
      .thompson(Regex::Automata::NFA::NFA.config.shrink(true))
      .build("[a-z]+")

    dfa.get_nfa.is_reverse.should be_true
  end

  it "retains the requested cache capacity when the effective capacity is raised" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(
        Regex::Automata::Hybrid::DFA.config
          .cache_capacity(0)
          .skip_cache_capacity_check(true)
      )
      .build("a")

    dfa.get_config.get_cache_capacity.should eq(0)
    dfa.get_cache_capacity.should eq(
      dfa.get_config.get_minimum_cache_capacity(dfa.get_nfa)
    )
  end

  it "ports Rust's per-pattern start-state example" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.starts_for_each_pattern(true))
      .build_many(["[a-z0-9]{6}", "[a-z][a-z0-9]{5}"])
    cache = dfa.create_cache
    haystack = "bar foo123"

    dfa.try_search_fwd(cache, Regex::Automata::Input.new(haystack)).should eq(
      Regex::Automata::HalfMatch.must(0, 10)
    )
    dfa.try_search_fwd(cache, Regex::Automata::Input.new(haystack).range(4...10)).should eq(
      Regex::Automata::HalfMatch.must(0, 10)
    )
    pattern_input = Regex::Automata::Input.new(haystack)
      .range(4...10)
      .anchored(Regex::Automata::Anchored::Pattern, Regex::Automata::PatternID.new(1))
    dfa.try_search_fwd(cache, pattern_input).should eq(
      Regex::Automata::HalfMatch.must(1, 10)
    )
  end

  it "ports Rust's specialized versus ordinary start-state tag examples" do
    specialized = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.specialize_start_states(true))
      .build("[a-z]+")
    ordinary = Regex::Automata::Hybrid::DFA.new("[a-z]+")
    input = Regex::Automata::Input.new("123 foobar 4567")

    start = specialized.start_state_forward(specialized.create_cache, input)
    start.should be_a(Regex::Automata::Hybrid::LazyStateID)
    start.as(Regex::Automata::Hybrid::LazyStateID).is_tagged.should be_true
    start.as(Regex::Automata::Hybrid::LazyStateID).is_start.should be_true

    start = ordinary.start_state_forward(ordinary.create_cache, input)
    start.should be_a(Regex::Automata::Hybrid::LazyStateID)
    start.as(Regex::Automata::Hybrid::LazyStateID).is_tagged.should be_false
    start.as(Regex::Automata::Hybrid::LazyStateID).is_start.should be_false
  end

  it "accepts an explicit start configuration for forward or reverse contexts" do
    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.quit('x'.ord.to_u8, true))
      .build("a")
    cache = dfa.create_cache

    dfa.start_state(cache, Regex::Automata::StartConfig.new('x'.ord.to_u8)).should be_a(
      Regex::Automata::Hybrid::StartError
    )
    dfa.start_state(cache, Regex::Automata::StartConfig.new).should be_a(
      Regex::Automata::Hybrid::LazyStateID
    )
    pattern = Regex::Automata::StartConfig.new.anchored(
      Regex::Automata::Anchored::Pattern,
      Regex::Automata::PatternID.new(0)
    )
    unsupported = dfa.start_state(cache, pattern)
    unsupported.should be_a(Regex::Automata::Hybrid::StartError)
    unsupported.as(Regex::Automata::Hybrid::StartError).pattern.should eq(
      Regex::Automata::PatternID.new(0)
    )
  end

  it "specializes starts automatically for a prefilter unless explicitly overridden" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo"]
    ).not_nil!

    with_pre = Regex::Automata::Hybrid::DFA.config.prefilter(pre)
    with_pre.get_specialize_start_states.should be_true
    without_pre = Regex::Automata::Hybrid::DFA.config.prefilter(nil)
    without_pre.get_specialize_start_states.should be_false
    explicit = Regex::Automata::Hybrid::DFA.config.specialize_start_states(false).prefilter(pre)
    explicit.get_specialize_start_states.should be_false
  end

  it "uses a correct prefilter and demonstrates Rust's incorrect-prefilter contract" do
    good = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo", "bar"]
    ).not_nil!
    bad = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo", "car"]
    ).not_nil!
    input = Regex::Automata::Input.new("foo1 barfox bar")

    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.prefilter(good))
      .build("(foo|bar)[a-z]+")
    dfa.try_search_fwd(dfa.create_cache, input).should eq(
      Regex::Automata::HalfMatch.must(0, 11)
    )

    dfa = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.prefilter(bad))
      .build("(foo|bar)[a-z]+")
    dfa.try_search_fwd(dfa.create_cache, input).should be_nil
  end

  it "combines separately built forward and reverse DFAs" do
    forward = Regex::Automata::Hybrid::DFA.new("foo[0-9]+")
    reverse = Regex::Automata::Hybrid::Builder.new
      .configure(Regex::Automata::Hybrid::DFA.config.match_kind(Regex::Automata::MatchKind::All))
      .thompson(Regex::Automata::NFA::NFA.config.reverse(true))
      .build("foo[0-9]+")
    re = Regex::Automata::Hybrid::Regex.builder.build_from_dfas(forward, reverse)
    cache = re.create_cache

    re.is_match(cache, "foo123").should be_true
    re.find(cache, "xfoo123y").should eq(Regex::Automata::Match.must(0, 1...7))
  end

  it "retargets a two-DFA regex cache as in Rust's reset_cache example" do
    word = Regex::Automata::Hybrid::Regex.new("\\w")
    nonword = Regex::Automata::Hybrid::Regex.new("\\W")
    cache = word.create_cache

    word.find(cache, "Δ").should eq(Regex::Automata::Match.must(0, 0...2))
    nonword.reset_cache(cache)
    nonword.find(cache, "☃").should eq(Regex::Automata::Match.must(0, 0...3))
  end

  it "matches every haystack with always_match and reports one pattern" do
    dfa = Regex::Automata::Hybrid::DFA.always_match
    cache = dfa.create_cache

    dfa.pattern_len.should eq(1)
    dfa.try_search_fwd(cache, Regex::Automata::Input.new("")).should eq(
      Regex::Automata::HalfMatch.must(0, 0)
    )
    dfa.try_search_fwd(cache, Regex::Automata::Input.new("foo")).should eq(
      Regex::Automata::HalfMatch.must(0, 0)
    )
  end

  it "never matches with never_match and reports no patterns" do
    dfa = Regex::Automata::Hybrid::DFA.never_match
    cache = dfa.create_cache

    dfa.pattern_len.should eq(0)
    dfa.try_search_fwd(cache, Regex::Automata::Input.new("")).should be_nil
    dfa.try_search_fwd(cache, Regex::Automata::Input.new("foo")).should be_nil
  end
end
