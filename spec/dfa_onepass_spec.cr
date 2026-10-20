require "./spec_helper"
require "./support/vendor_regex_suite"

private def onepass_pid(id : Int32) : Regex::Automata::PatternID
  Regex::Automata::PatternID.new(id)
end

private record OnePassAnchoredFixture,
  name : String,
  regex : String,
  haystack : Bytes,
  matches : Array(Tuple(Int32, Int32)),
  bounds : Tuple(Int32, Int32),
  unicode : Bool,
  earliest : Bool,
  match_kind : Regex::Automata::MatchKind

private def onepass_anchored_fixtures : Array(OnePassAnchoredFixture)
  VendorRegexSuite.load.cases("anchored").select(&.anchored).map do |fixture|
    OnePassAnchoredFixture.new(
      fixture.name, fixture.patterns[0], fixture.haystack,
      fixture.matches.map(&.span), fixture.bounds, fixture.unicode,
      fixture.search_kind == "earliest",
      fixture.match_kind == "all" ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst
    )
  end
end

private def assert_onepass_anchored_fixtures(base_config : Regex::Automata::DFA::OnePass::Config) : Nil
  exercised = 0
  fixtures = onepass_anchored_fixtures
  fixtures.size.should eq(12)

  fixtures.each do |fixture|
    builder = Regex::Automata::DFA::OnePass::DFA.builder
      .configure(
        base_config.overwrite(
          Regex::Automata::DFA::OnePass::DFA.config
            .match_kind(fixture.match_kind)
        )
      )
      .syntax(Regex::Automata::Syntax::Config.new.unicode(fixture.unicode))

    begin
      re = builder.build(fixture.regex)
      cache = re.create_cache
      caps = re.create_captures
      input = Regex::Automata::Input.new(fixture.haystack)
        .range(fixture.bounds[0]...fixture.bounds[1])
        .anchored(Regex::Automata::Anchored::Yes)
        .earliest(fixture.earliest)

      re.try_search(cache, input, caps).should be_nil
      if expected = fixture.matches.first?
        caps.get_match.should eq(
          Regex::Automata::Match.must(0, expected[0]...expected[1])
        )
      else
        caps.get_match.should be_nil
      end
      exercised += 1
    rescue error : Regex::Automata::DFA::OnePass::BuildError
      next if error.kind == Regex::Automata::DFA::OnePass::BuildError::Kind::NotOnePass

      raise error
    end
  end

  exercised.should be > 0
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
    re.create_cache.memory_usage.should eq(0)

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

  it "uses an internal earliest search for existence checks" do
    re = Regex::Automata::DFA::OnePass::DFA.new("(abc)+")
    input = Regex::Automata::Input.new("abcabc")

    re.is_match(re.create_cache, input).should be_true
    input.get_earliest.should be_false
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

  it "sizes compiled capture scratch space to each search buffer" do
    re = Regex::Automata::DFA::OnePass::DFA.new("(a)(b)")
    cache = re.create_cache

    re.is_match(cache, "ab").should be_true
    cache.compiled_slot_len.should eq(0)

    slots = Array(Regex::Automata::NonMaxUsize?).new(3, nil)
    re.try_search_slots(
      cache,
      Regex::Automata::Input.new("ab").anchored(Regex::Automata::Anchored::Yes),
      slots
    ).should eq(onepass_pid(0))
    cache.compiled_slot_len.should eq(1)
    slots[0].not_nil!.get.should eq(0)
    slots[1].not_nil!.get.should eq(2)
    slots[2].not_nil!.get.should eq(0)
  end

  it "matches the upstream build-time one-pass checks and limits" do
    Regex::Automata::DFA::OnePass::DFA.new("a*b")
    Regex::Automata::DFA::OnePass::DFA.new("\\w")
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

  it "derives one-pass conflicts from the Thompson NFA" do
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /conflicting transition/) do
      Regex::Automata::DFA::OnePass::DFA.new("[ab]*a")
    end
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /conflicting transition/) do
      Regex::Automata::DFA::OnePass::DFA.new("(?:ab|a)b")
    end

    Regex::Automata::DFA::OnePass::DFA.new("(?:foo|fo)bar")
  end

  it "preserves upstream one-pass build error kinds and causes" do
    error = expect_raises(Regex::Automata::DFA::OnePass::BuildError) do
      Regex::Automata::DFA::OnePass::DFA.new("a*[ab]")
    end
    error.kind.should eq(Regex::Automata::DFA::OnePass::BuildError::Kind::NotOnePass)
    error.source.should be_nil

    error = expect_raises(Regex::Automata::DFA::OnePass::BuildError) do
      Regex::Automata::DFA::OnePass::DFA.builder
        .configure(Regex::Automata::DFA::OnePass::DFA.config.size_limit(1))
        .build("abc")
    end
    error.kind.should eq(Regex::Automata::DFA::OnePass::BuildError::Kind::ExceededSizeLimit)
    error.size_limit_exceeded?.should be_true
    error.size_limit.should eq(1)

    error = expect_raises(Regex::Automata::DFA::OnePass::BuildError) do
      Regex::Automata::DFA::OnePass::DFA.new("(")
    end
    error.kind.should eq(Regex::Automata::DFA::OnePass::BuildError::Kind::NFA)
    error.source.should_not be_nil
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

  it "rejects assertions outside Rust's one-pass transition representation" do
    error = expect_raises(Regex::Automata::DFA::OnePass::BuildError) do
      Regex::Automata::DFA::OnePass::DFA.new("\\b{start}")
    end
    error.kind.should eq(Regex::Automata::DFA::OnePass::BuildError::Kind::UnsupportedLook)
    error.look.should eq(Regex::Automata::Look::WordStartUnicode)
  end

  it "executes compiled one-pass assertion transitions and match states" do
    boundary = Regex::Automata::DFA::OnePass::DFA.new("(?-u:\\b)abc")
    cache = boundary.create_cache
    boundary.find(cache, Regex::Automata::Input.new("abc").anchored(Regex::Automata::Anchored::Yes)).should eq(
      Regex::Automata::Match.must(0, 0...3)
    )
    boundary.find(cache, Regex::Automata::Input.new("zabc").span(1...4).anchored(Regex::Automata::Anchored::Yes)).should be_nil

    end_anchor = Regex::Automata::DFA::OnePass::DFA.new("abc$")
    cache = end_anchor.create_cache
    end_anchor.find(cache, Regex::Automata::Input.new("abc").anchored(Regex::Automata::Anchored::Yes)).should eq(
      Regex::Automata::Match.must(0, 0...3)
    )
    end_anchor.find(cache, Regex::Automata::Input.new("abcx").anchored(Regex::Automata::Anchored::Yes)).should be_nil
  end

  it "honors configured line terminators without byte classes in compiled searches" do
    line_terminator = ';'.ord.to_u8
    re = Regex::Automata::DFA::OnePass::DFA.builder
      .configure(Regex::Automata::DFA::OnePass::DFA.config.byte_classes(false))
      .syntax(Regex::Automata::Syntax::Config.new.line_terminator(line_terminator))
      .thompson(
        Regex::Automata::NFA::NFA.config
          .look_matcher(Regex::Automata::LookMatcher.new(line_terminator))
      )
      .build("(?m)^abc$")
    cache = re.create_cache
    re.find(
      cache,
      Regex::Automata::Input.new("x;abc;y").span(2...5).anchored(Regex::Automata::Anchored::Yes)
    ).should eq(Regex::Automata::Match.must(0, 2...5))
  end

  it "uses longest-match semantics for MatchKind::All" do
    default = Regex::Automata::DFA::OnePass::DFA.new("(abc)+?")
    default.find(default.create_cache, "abcabc").should eq(
      Regex::Automata::Match.must(0, 0...3)
    )

    longest = Regex::Automata::DFA::OnePass::DFA.builder
      .configure(
        Regex::Automata::DFA::OnePass::DFA.config
          .match_kind(Regex::Automata::MatchKind::All)
      )
      .build("(abc)+?")
    longest.find(longest.create_cache, "abcabc").should eq(
      Regex::Automata::Match.must(0, 0...6)
    )
  end

  it "agrees with the Thompson oracle on a supported anchored matrix" do
    {
      "a*b"           => "aaab",
      "abc|a"         => "abc",
      "(abc)+?"       => "abcabc",
      "(?-u:\\b)abc"  => "abc",
      "(?m)^abc$"     => "abc\n",
      "(?:foo|fo)bar" => "foobar",
    }.each do |pattern, haystack|
      input = Regex::Automata::Input.new(haystack).anchored(Regex::Automata::Anchored::Yes)
      onepass = Regex::Automata::DFA::OnePass::DFA.new(pattern)
      pikevm = Regex::Automata::NFA::PikeVM.new(pattern)

      onepass.find(onepass.create_cache, input).should eq(
        pikevm.find(pikevm.create_cache, input)
      )
    end
  end

  it "honors one-pass size limits" do
    expect_raises(Regex::Automata::DFA::OnePass::BuildError, /size limit/) do
      Regex::Automata::DFA::OnePass::DFA.builder
        .configure(Regex::Automata::DFA::OnePass::DFA.config.size_limit(1))
        .build("abc")
    end
  end

  it "does not report UTF-8 empty matches inside a code point" do
    input = Regex::Automata::Input.new("☃").span(1...2)

    utf8 = Regex::Automata::DFA::OnePass::DFA.new("a*")
    utf8.is_match(utf8.create_cache, input).should be_false
    utf8.try_search_slots(
      utf8.create_cache,
      input.anchored(Regex::Automata::Anchored::Yes),
      [] of Regex::Automata::NonMaxUsize?
    ).should be_nil

    binary = Regex::Automata::DFA::OnePass::DFA.builder
      .thompson(Regex::Automata::NFA::NFA.config.utf8(false))
      .build("a*")
    binary.is_match(binary.create_cache, input).should be_true
  end

  it "runs the vendored anchored fixture corpus for admitted one-pass patterns" do
    assert_onepass_anchored_fixtures(Regex::Automata::DFA::OnePass::DFA.config)
  end

  it "runs anchored fixtures with one-pass byte classes disabled" do
    assert_onepass_anchored_fixtures(
      Regex::Automata::DFA::OnePass::DFA.config.byte_classes(false)
    )
  end

  it "runs anchored fixtures with one-pass starts for each pattern" do
    assert_onepass_anchored_fixtures(
      Regex::Automata::DFA::OnePass::DFA.config.starts_for_each_pattern(true)
    )
  end
end
