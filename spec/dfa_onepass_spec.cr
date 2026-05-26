require "./spec_helper"

private def onepass_pid(id : Int32) : Regex::Automata::PatternID
  Regex::Automata::PatternID.new(id)
end

describe Regex::Automata::DFA::OnePass::Config do
  it "exposes the vendored default configuration and overwrite semantics" do
    base = Regex::Automata::DFA::OnePass::Config.new
    merged = base.overwrite(
      Regex::Automata::DFA::OnePass::Config.new
        .match_kind(Regex::Automata::MatchKind::All)
        .starts_for_each_pattern(true)
        .byte_classes(false)
        .size_limit(123)
    )

    base.get_match_kind.should eq(Regex::Automata::MatchKind::LeftmostFirst)
    base.get_starts_for_each_pattern.should be_false
    base.get_byte_classes.should be_true
    base.get_size_limit.should be_nil

    merged.get_match_kind.should eq(Regex::Automata::MatchKind::All)
    merged.get_starts_for_each_pattern.should be_true
    merged.get_byte_classes.should be_false
    merged.get_size_limit.should eq(123)
  end
end

describe Regex::Automata::DFA::OnePass::DFA do
  it "builds from constructors, builders, and NFAs" do
    syntax = Regex::Automata::Syntax::Config.new.utf8(false)
    thompson = Regex::Automata::NFA::NFA.config.utf8(false)

    re = Regex::Automata::DFA::OnePass::DFA.builder
      .configure(
        Regex::Automata::DFA::OnePass::DFA.config
          .match_kind(Regex::Automata::MatchKind::All)
          .starts_for_each_pattern(true)
          .byte_classes(false)
      )
      .syntax(syntax)
      .thompson(thompson)
      .build("foo(?-u:[\\xFF])bar")

    re.get_match_kind.should eq(Regex::Automata::MatchKind::All)
    re.get_config.get_starts_for_each_pattern.should be_true
    re.get_config.get_byte_classes.should be_false
    re.get_nfa.is_utf8.should be_false
    re.byte_classes.is_singleton.should be_true
    re.alphabet_len.should eq(256)
    re.stride.should be >= re.alphabet_len
    re.state_len.should be > 0
    re.pattern_len.should eq(1)
    re.memory_usage.should be > 0
    re.create_cache.memory_usage.should be > 0

    always = Regex::Automata::DFA::OnePass::DFA.always_match
    cache = always.create_cache
    always.find(cache, "foo").should eq(Regex::Automata::Match.must(0, 0...0))

    never = Regex::Automata::DFA::OnePass::DFA.never_match
    cache = never.create_cache
    never.find(cache, "foo").should be_nil

    many = Regex::Automata::DFA::OnePass::DFA.new_many(["[a-z]+", "[0-9]+"])
    many.pattern_len.should eq(2)

    nfa = Regex::Automata::NFA::NFA.compiler.build("[A-Z]+")
    from_nfa = Regex::Automata::DFA::OnePass::DFA.new_from_nfa(nfa)
    cache = from_nfa.create_cache
    from_nfa.find(
      cache,
      Regex::Automata::Input.new("123ABC456").range(3...6)
    ).should eq(
      Regex::Automata::Match.must(0, 3...6)
    )
  end

  it "coerces high-level APIs to anchored searches but rejects unsupported low-level modes" do
    re = Regex::Automata::DFA::OnePass::DFA.new("[0-9]+")
    cache = re.create_cache

    re.is_match(cache, "123").should be_true
    re.is_match(cache, Regex::Automata::Input.new("abc123")).should be_false
    re.find(cache, Regex::Automata::Input.new("abc123")).should be_nil

    caps = re.create_captures
    re.captures(cache, Regex::Automata::Input.new("123abc"), caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 0...3))

    err = re.try_search(
      cache,
      Regex::Automata::Input.new("123abc"),
      caps
    )
    err.should be_a(Regex::Automata::MatchError)
    err = err.as(Regex::Automata::MatchError)
    err.unsupported_anchored?.should be_true
    err.mode.should eq(Regex::Automata::Anchored::No)

    err = re.try_search_slots(
      cache,
      Regex::Automata::Input.new("123").anchored_pattern(onepass_pid(0)),
      Array(Regex::Automata::NonMaxUsize?).new(2, nil)
    )
    err.should be_a(Regex::Automata::MatchError)
    err = err.as(Regex::Automata::MatchError)
    err.unsupported_anchored?.should be_true
    err.mode.should eq(Regex::Automata::Anchored::Pattern)
  end

  it "supports starts_for_each_pattern for anchored pattern searches" do
    re = Regex::Automata::DFA::OnePass::DFA.builder
      .configure(
        Regex::Automata::DFA::OnePass::DFA.config
          .starts_for_each_pattern(true)
      )
      .build_many(["[a-z]+", "[0-9]+"])
    cache = re.create_cache
    caps = re.create_captures

    input = Regex::Automata::Input.new("123abc")
      .anchored(Regex::Automata::Anchored::Yes)
    re.try_search(cache, input, caps).should be_nil
    caps.get_match.should eq(Regex::Automata::Match.must(1, 0...3))

    input = Regex::Automata::Input.new("123abc").anchored_pattern(onepass_pid(0))
    re.try_search(cache, input, caps).should be_nil
    caps.get_match.should be_nil
  end

  it "resets caches across one-pass DFAs" do
    first = Regex::Automata::DFA::OnePass::DFA.new("abc")
    second = Regex::Automata::DFA::OnePass::DFA.new("[0-9]+")
    cache = first.create_cache

    first.find(cache, "abc").should eq(Regex::Automata::Match.must(0, 0...3))
    second.reset_cache(cache)
    second.find(cache, "123").should eq(Regex::Automata::Match.must(0, 0...3))
  end

  it "preserves slot behavior for zero-repetition and extra-slot regressions" do
    expr = Regex::Automata::DFA::OnePass::DFA.new("(abc)(ABC){0}")
    input = Regex::Automata::Input.new("abcABC")
      .span(0...6)
      .anchored(Regex::Automata::Anchored::Yes)
    cache = expr.create_cache
    slots = Array(Regex::Automata::NonMaxUsize?).new(4, nil)

    expr.try_search_slots(cache, input, slots).should eq(onepass_pid(0))
    slots[0].not_nil!.get.should eq(0)
    slots[1].not_nil!.get.should eq(3)
    slots[2].not_nil!.get.should eq(0)
    slots[3].not_nil!.get.should eq(3)

    2.times { slots << nil }
    expr.try_search_slots(cache, input, slots).should eq(onepass_pid(0))
    slots[2].not_nil!.get.should eq(0)
    slots[3].not_nil!.get.should eq(3)
    slots[4].should be_nil
    slots[5].should be_nil

    normal = Regex::Automata::DFA::OnePass::DFA.new("abc")
    input = Regex::Automata::Input.new("abc")
      .span(0...3)
      .anchored(Regex::Automata::Anchored::Yes)
    cache = normal.create_cache
    slots = Array(Regex::Automata::NonMaxUsize?).new(4, nil)
    normal.try_search_slots(cache, input, slots).should eq(onepass_pid(0))
    slots[0].not_nil!.get.should eq(0)
    slots[1].not_nil!.get.should eq(3)
  end

  it "matches the upstream build-time one-pass checks and limits" do
    Regex::Automata::DFA::OnePass::DFA.new("a*b")
    Regex::Automata::DFA::OnePass::DFA.new("(?-u)\\w*\\s")
    Regex::Automata::DFA::OnePass::DFA.new("(?s:.)*?")
    Regex::Automata::DFA::OnePass::DFA.builder
      .syntax(Regex::Automata::Syntax::Config.new.utf8(false))
      .build("(?s-u:.)*?")

    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /conflicting transition/) do
      Regex::Automata::DFA::OnePass::DFA.new("a*[ab]")
    end
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /multiple epsilon transitions to same state/) do
      Regex::Automata::DFA::OnePass::DFA.new("(^|$)a")
    end
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /multiple epsilon transitions to match state/) do
      Regex::Automata::DFA::OnePass::DFA.new_many(["^", "$"])
    end
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /not one-pass/) do
      Regex::Automata::DFA::OnePass::DFA.new("a*a")
    end
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /not one-pass/) do
      Regex::Automata::DFA::OnePass::DFA.new("(?s-u:.)*?")
    end
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /not one-pass/) do
      Regex::Automata::DFA::OnePass::DFA.new("(?s:.)*?a")
    end
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /not one-pass/) do
      Regex::Automata::DFA::OnePass::DFA.new("\\w*\\s")
    end

    expect_raises(Regex::Automata::DFA::OnePass::BuildError) do
      Regex::Automata::DFA::OnePass::DFA.new(
        "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)(m)(n)(o)(p)(q)"
      )
    end
    Regex::Automata::DFA::OnePass::DFA.new(
      "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)(m)(n)(o)(p)"
    )
  end

  it "accepts the upstream supported assertion patterns" do
    [
      "^",
      "$",
      "(?m)^",
      "(?m)$",
      "(?Rm)^",
      "(?Rm)$",
      "\\b",
      "\\B",
      "(?-u)\\b",
      "(?-u)\\B",
    ].each do |pattern|
      Regex::Automata::DFA::OnePass::DFA.new(pattern)
    end
  end

  it "honors one-pass size limits" do
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /size limit/) do
      Regex::Automata::DFA::OnePass::DFA.builder
        .configure(Regex::Automata::DFA::OnePass::DFA.config.size_limit(1))
        .build("abc")
    end
  end
end
