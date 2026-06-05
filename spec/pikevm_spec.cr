require "./spec_helper"

private def pikevm_build(pattern : String, *,
                         prefilter : Regex::Automata::Prefilter? = nil,
                         match_kind : Regex::Automata::MatchKind = Regex::Automata::MatchKind::LeftmostFirst,
                         syntax : Regex::Automata::Syntax::Config = Regex::Automata::Syntax::Config.new,
                         thompson : Regex::Automata::HirCompilerConfig = Regex::Automata::NFA::NFA.config) : Regex::Automata::NFA::PikeVM
  Regex::Automata::NFA::PikeVM.builder
    .configure(
      Regex::Automata::NFA::PikeVM.config
        .match_kind(match_kind)
        .prefilter(prefilter)
    )
    .syntax(syntax)
    .thompson(thompson)
    .build(pattern)
end

private def pikevm_pid(id : Int32) : Regex::Automata::PatternID
  Regex::Automata::PatternID.new(id)
end

describe Regex::Automata::NFA::PikeVM do
  it "builds from patterns, NFAs, and constructor helpers" do
    prefilter = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo", "bar"]
    ).not_nil!
    syntax = Regex::Automata::Syntax::Config.new.case_insensitive(true)
    thompson = Regex::Automata::NFA::NFA.config.utf8(false)

    re = Regex::Automata::NFA::PikeVM.builder
      .configure(
        Regex::Automata::NFA::PikeVM.config
          .match_kind(Regex::Automata::MatchKind::All)
          .prefilter(prefilter)
      )
      .syntax(syntax)
      .thompson(thompson)
      .build("foo")

    re.pattern_len.should eq(1)
    re.get_match_kind.should eq(Regex::Automata::MatchKind::All)
    re.get_prefilter.should eq(prefilter)
    re.get_config.get_match_kind.should eq(Regex::Automata::MatchKind::All)
    re.get_nfa.is_utf8.should be_false
    re.memory_usage.should eq(re.get_nfa.memory_usage)
    re.create_captures.group_info.should eq(re.get_nfa.group_info)
    re.create_cache.memory_usage.should be > 0

    built_many = Regex::Automata::NFA::PikeVM.new_many(["[a-z]+", "[0-9]+"])
    built_many.pattern_len.should eq(2)

    nfa = Regex::Automata::NFA::NFA.compiler.build("[A-Z]+")
    built_from_nfa = Regex::Automata::NFA::PikeVM.new_from_nfa(nfa)
    cache = built_from_nfa.create_cache
    built_from_nfa.find(cache, "123ABC456").should eq(
      Regex::Automata::Match.must(0, 3...6)
    )
  end

  it "finds and iterates matches for single and multiple patterns" do
    re = Regex::Automata::NFA::PikeVM.new("foo[0-9]+bar")
    cache = re.create_cache

    re.find(cache, "zzzfoo12345barzzz").should eq(
      Regex::Automata::Match.must(0, 3...14)
    )
    re.is_match(cache, "zzzfoo12345barzzz").should be_true
    re.is_match(cache, "zzzquuxzzz").should be_false

    many = Regex::Automata::NFA::PikeVM.new_many(["[a-z]+", "[0-9]+"])
    cache = many.create_cache
    many.find_iter(cache, "abc 1 foo 4567 0 quux").to_a.should eq([
      Regex::Automata::Match.must(0, 0...3),
      Regex::Automata::Match.must(1, 4...5),
      Regex::Automata::Match.must(0, 6...9),
      Regex::Automata::Match.must(1, 10...14),
      Regex::Automata::Match.must(1, 15...16),
      Regex::Automata::Match.must(0, 17...21),
    ])
  end

  it "reports captures and capture iterators with stable snapshots" do
    re = Regex::Automata::NFA::PikeVM.new("(?P<year>[0-9]{4})-[0-9]{2}")
    cache = re.create_cache
    caps = re.create_captures

    re.captures(cache, "2010-03 2016-10 2020-11", caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 0...7))
    caps.get_group_by_name("year").should eq(Regex::Automata::Span.new(0, 4))

    results = re.captures_iter(cache, "2010-03 2016-10 2020-11").to_a
    results.map(&.get_match).should eq([
      Regex::Automata::Match.must(0, 0...7),
      Regex::Automata::Match.must(0, 8...15),
      Regex::Automata::Match.must(0, 16...23),
    ])
    results.map(&.get_group_by_name("year")).should eq([
      Regex::Automata::Span.new(0, 4),
      Regex::Automata::Span.new(8, 12),
      Regex::Automata::Span.new(16, 20),
    ])
    results[0].get_group_by_name("year").should eq(Regex::Automata::Span.new(0, 4))
  end

  it "supports overlapping pattern discovery with MatchKind::All" do
    re = Regex::Automata::NFA::PikeVM.builder
      .configure(
        Regex::Automata::NFA::PikeVM.config
          .match_kind(Regex::Automata::MatchKind::All)
      )
      .build_many(["[a-z]+", "[a-z]{3}", "[a-z]{4}"])
    cache = re.create_cache
    patset = Regex::Automata::PatternSet.new(re.pattern_len)

    re.which_overlapping_matches(
      cache,
      Regex::Automata::Input.new("abcd").anchored(Regex::Automata::Anchored::Yes),
      patset
    )

    patset.iter.to_a.should eq([pikevm_pid(0), pikevm_pid(1), pikevm_pid(2)])
  end

  it "supports explicit prefilters and cache reset" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo", "bar"]
    ).not_nil!
    re = pikevm_build("(foo|bar)[a-z]+", prefilter: pre)
    cache = re.create_cache

    re.find(cache, "foo1 barfox bar").should eq(
      Regex::Automata::Match.must(0, 5...11)
    )

    other = Regex::Automata::NFA::PikeVM.new("[0-9]+")
    other.reset_cache(cache)
    other.find(cache, "abc123xyz").should eq(
      Regex::Automata::Match.must(0, 3...6)
    )
  end

  it "honors UTF-8 empty-match semantics and supports disabling them" do
    utf8 = Regex::Automata::NFA::PikeVM.new("")
    cache = utf8.create_cache
    utf8.find_iter(cache, "a☃z").to_a.should eq([
      Regex::Automata::Match.must(0, 0...0),
      Regex::Automata::Match.must(0, 1...1),
      Regex::Automata::Match.must(0, 4...4),
      Regex::Automata::Match.must(0, 5...5),
    ])

    no_utf8 = Regex::Automata::NFA::PikeVM.builder
      .thompson(Regex::Automata::NFA::NFA.config.utf8(false))
      .build("")
    cache = no_utf8.create_cache
    no_utf8.find_iter(cache, "a☃z").to_a.should eq([
      Regex::Automata::Match.must(0, 0...0),
      Regex::Automata::Match.must(0, 1...1),
      Regex::Automata::Match.must(0, 2...2),
      Regex::Automata::Match.must(0, 3...3),
      Regex::Automata::Match.must(0, 4...4),
      Regex::Automata::Match.must(0, 5...5),
    ])
  end

  it "supports Unicode word boundaries by default" do
    re = Regex::Automata::NFA::PikeVM.new("\\b\\w+\\b")
    cache = re.create_cache

    re.find_iter(cache, "Шерлок Холмс").to_a.should eq([
      Regex::Automata::Match.must(0, 0...12),
      Regex::Automata::Match.must(0, 13...23),
    ])
  end

  it "allows search_slots with extra NonMaxUsize capacity" do
    re = Regex::Automata::NFA::PikeVM.new("abc")
    cache = re.create_cache
    input = Regex::Automata::Input.new("abc")
      .span(0...3)
      .anchored(Regex::Automata::Anchored::Yes)
    slots = Array(Regex::Automata::NonMaxUsize?).new(4, nil)

    re.search_slots(cache, input, slots).should eq(pikevm_pid(0))
    slots[0].not_nil!.get.should eq(0)
    slots[1].not_nil!.get.should eq(3)
    slots[2].should be_nil
    slots[3].should be_nil
  end

  it "builds always-match and never-match helpers" do
    always = Regex::Automata::NFA::PikeVM.always_match
    cache = always.create_cache
    always.find(cache, "").should eq(Regex::Automata::Match.must(0, 0...0))
    always.find(cache, "foo").should eq(Regex::Automata::Match.must(0, 0...0))

    never = Regex::Automata::NFA::PikeVM.never_match
    cache = never.create_cache
    never.find(cache, "").should be_nil
    never.find(cache, "foo").should be_nil
  end
end
