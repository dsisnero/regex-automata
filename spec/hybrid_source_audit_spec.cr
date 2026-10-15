require "./spec_helper"

describe "pinned Rust hybrid DFA API examples" do
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
