require "./spec_helper"

private def backtrack_pid(id : Int32) : Regex::Automata::PatternID
  Regex::Automata::PatternID.new(id)
end

private def backtrack_build(pattern : String, *,
                            prefilter : Regex::Automata::Prefilter? = nil,
                            visited_capacity : Int64? = nil,
                            syntax : Regex::Automata::Syntax::Config = Regex::Automata::Syntax::Config.new,
                            thompson : Regex::Automata::HirCompilerConfig = Regex::Automata::NFA::NFA.config) : Regex::Automata::NFA::Backtrack::BoundedBacktracker
  builder = Regex::Automata::NFA::Backtrack::BoundedBacktracker.builder
  config = Regex::Automata::NFA::Backtrack::BoundedBacktracker.config
  config.prefilter(prefilter) unless prefilter.nil?
  config.visited_capacity(visited_capacity.not_nil!) unless visited_capacity.nil?
  builder.configure(config)
  builder.syntax(syntax)
  builder.thompson(thompson)
  builder.build(pattern)
end

describe Regex::Automata::NFA::Backtrack::Config do
  it "exposes defaults and overwrite semantics" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo", "bar"]
    ).not_nil!
    base = Regex::Automata::NFA::Backtrack::Config.new
    merged = base.overwrite(
      Regex::Automata::NFA::Backtrack::Config.new
        .prefilter(pre)
        .visited_capacity(1024)
    )

    base.get_prefilter.should be_nil
    base.get_visited_capacity.should eq(256 * (1 << 10))
    merged.get_prefilter.should eq(pre)
    merged.get_visited_capacity.should eq(1024)
  end
end

describe Regex::Automata::NFA::Backtrack do
  it "computes minimum visited capacity for an input" do
    nfa = Regex::Automata::NFA::NFA.new("abc")
    input = Regex::Automata::Input.new("abcdef")

    Regex::Automata::NFA::Backtrack.min_visited_capacity(nfa, input).should eq(
      ((nfa.states.size * (input.get_span.length + 1)) + 7) // 8
    )
  end
end

describe Regex::Automata::NFA::Backtrack::BoundedBacktracker do
  it "builds from constructors, builders, and NFAs" do
    syntax = Regex::Automata::Syntax::Config.new.utf8(false)
    thompson = Regex::Automata::NFA::NFA.config.utf8(false)
    re = backtrack_build(
      "foo(?-u:[\\xFF])bar",
      visited_capacity: 1_i64 << 20,
      syntax: syntax,
      thompson: thompson
    )

    re.get_nfa.is_utf8.should be_false
    re.get_prefilter.should be_nil
    re.pattern_len.should eq(1)
    re.memory_usage.should eq(re.get_nfa.memory_usage)
    re.create_cache.memory_usage.should be > 0
    re.max_haystack_len.should be > 0

    always = Regex::Automata::NFA::Backtrack::BoundedBacktracker.always_match
    cache = always.create_cache
    always.try_find(cache, "foo").should eq(Regex::Automata::Match.must(0, 0...0))

    never = Regex::Automata::NFA::Backtrack::BoundedBacktracker.never_match
    cache = never.create_cache
    never.try_find(cache, "foo").should be_nil

    many = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new_many(["[a-z]+", "[0-9]+"])
    many.pattern_len.should eq(2)

    nfa = Regex::Automata::NFA::NFA.compiler.build("[A-Z]+")
    from_nfa = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new_from_nfa(nfa)
    cache = from_nfa.create_cache
    from_nfa.try_find(cache, "123ABC456").should eq(
      Regex::Automata::Match.must(0, 3...6)
    )
  end

  it "supports leftmost matching, captures, and iterators" do
    re = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("foo(?P<num>[0-9]+)")
    cache = re.create_cache
    caps = re.create_captures

    re.try_is_match(cache, "foo123").should be_true
    re.try_is_match(cache, "bar").should be_false

    re.try_find(cache, "xfoo123y").should eq(Regex::Automata::Match.must(0, 1...7))
    re.try_captures(cache, "xfoo123y", caps).should be_nil
    caps.get_group_by_name("num").should eq(Regex::Automata::Span.new(4, 7))

    matches = [] of Regex::Automata::Match
    it = re.try_find_iter(cache, "foo1 foo12 foo123")
    while item = it.next
      item.should be_a(Regex::Automata::Match)
      matches << item.as(Regex::Automata::Match)
    end
    matches.should eq([
      Regex::Automata::Match.must(0, 0...4),
      Regex::Automata::Match.must(0, 5...10),
      Regex::Automata::Match.must(0, 11...17),
    ])

    spans = [] of Regex::Automata::Span
    it = re.try_captures_iter(cache, "foo1 foo12 foo123")
    while item = it.next
      item.should be_a(Regex::Automata::Captures)
      spans << item.as(Regex::Automata::Captures).get_group_by_name("num").not_nil!
    end
    spans.should eq([
      Regex::Automata::Span.new(3, 4),
      Regex::Automata::Span.new(8, 10),
      Regex::Automata::Span.new(14, 17),
    ])
  end

  it "supports prefilters, anchored pattern searches, and bounded context" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["foo", "bar"]
    ).not_nil!
    re = backtrack_build("(foo|bar)[a-z]+", prefilter: pre)
    cache = re.create_cache

    re.try_find(cache, "foo1 barfox bar").should eq(
      Regex::Automata::Match.must(0, 5...11)
    )

    multi = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new_many([
      "[a-z0-9]{6}",
      "[a-z][a-z0-9]{5}",
    ])
    cache = multi.create_cache
    caps = multi.create_captures
    multi.try_search(cache, Regex::Automata::Input.new("foo123"), caps).should be_nil
    caps.get_match.should eq(Regex::Automata::Match.must(0, 0...6))

    input = Regex::Automata::Input.new("foo123")
      .anchored_pattern(backtrack_pid(1))
    multi.try_search(cache, input, caps).should be_nil
    caps.get_match.should eq(Regex::Automata::Match.must(1, 0...6))

    bounded = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("\\b[0-9]{3}\\b")
    cache = bounded.create_cache
    caps = bounded.create_captures
    bounded.try_search(cache, Regex::Automata::Input.new("123"), caps).should be_nil
    caps.get_match.should eq(Regex::Automata::Match.must(0, 0...3))

    bounded.try_search(
      cache,
      Regex::Automata::Input.new("foo123bar").range(3...6),
      caps
    ).should be_nil
    caps.get_match.should be_nil
  end

  it "supports cache reset and Unicode word boundaries" do
    re1 = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("\\w")
    re2 = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("\\W")
    cache = re1.create_cache

    re1.try_find(cache, "Δ").should eq(Regex::Automata::Match.must(0, 0...2))
    re2.reset_cache(cache)
    re2.try_find(cache, "☃").should eq(Regex::Automata::Match.must(0, 0...3))

    boundary = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("\\b\\w+\\b")
    cache = boundary.create_cache
    matches = [] of Regex::Automata::Match
    it = boundary.try_find_iter(cache, "Шерлок Холмс")
    while item = it.next
      item.should be_a(Regex::Automata::Match)
      matches << item.as(Regex::Automata::Match)
    end
    matches.should eq([
      Regex::Automata::Match.must(0, 0...12),
      Regex::Automata::Match.must(0, 13...23),
    ])
  end

  it "preserves UTF-8 empty-match behavior and extra-slot regression behavior" do
    utf8 = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("")
    cache = utf8.create_cache
    matches = [] of Regex::Automata::Match
    it = utf8.try_find_iter(cache, "a☃z")
    while item = it.next
      item.should be_a(Regex::Automata::Match)
      matches << item.as(Regex::Automata::Match)
    end
    matches.should eq([
      Regex::Automata::Match.must(0, 0...0),
      Regex::Automata::Match.must(0, 1...1),
      Regex::Automata::Match.must(0, 4...4),
      Regex::Automata::Match.must(0, 5...5),
    ])

    no_utf8 = backtrack_build(
      "",
      syntax: Regex::Automata::Syntax::Config.new.utf8(false),
      thompson: Regex::Automata::NFA::NFA.config.utf8(false)
    )
    cache = no_utf8.create_cache
    matches = [] of Regex::Automata::Match
    it = no_utf8.try_find_iter(cache, "a☃z")
    while item = it.next
      item.should be_a(Regex::Automata::Match)
      matches << item.as(Regex::Automata::Match)
    end
    matches.should eq([
      Regex::Automata::Match.must(0, 0...0),
      Regex::Automata::Match.must(0, 1...1),
      Regex::Automata::Match.must(0, 2...2),
      Regex::Automata::Match.must(0, 3...3),
      Regex::Automata::Match.must(0, 4...4),
      Regex::Automata::Match.must(0, 5...5),
    ])

    normal = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("abc")
    input = Regex::Automata::Input.new("abc")
      .span(0...3)
      .anchored(Regex::Automata::Anchored::Yes)
    cache = normal.create_cache
    slots = Array(Regex::Automata::NonMaxUsize?).new(4, nil)
    normal.try_search_slots(cache, input, slots).should eq(backtrack_pid(0))
    slots[0].not_nil!.get.should eq(0)
    slots[1].not_nil!.get.should eq(3)
  end

  it "enforces visited-capacity bounds and max haystack length math" do
    re = backtrack_build("[0-9A-Za-z]{100}", visited_capacity: 10)
    re.max_haystack_len.should eq(0)

    bounded = backtrack_build("abc", visited_capacity: 1)
    cache = bounded.create_cache
    result = bounded.try_find(cache, "abc")
    result.should be_a(Regex::Automata::MatchError)
    error = result.as(Regex::Automata::MatchError)
    error.haystack_too_long?.should be_true
    error.len.should eq(3)

    iter = bounded.try_find_iter(cache, "abc")
    result = iter.next
    result.should be_a(Regex::Automata::MatchError)
    result.as(Regex::Automata::MatchError).haystack_too_long?.should be_true
  end
end
