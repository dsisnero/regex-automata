require "./spec_helper"

describe "pinned Rust hybrid regex wrapper contracts" do
  it "asserts that forward and reverse DFAs have the same pattern count" do
    forward = Regex::Automata::Hybrid::DFA.new("foo")
    reverse = Regex::Automata::Hybrid::DFA.new_many(["foo", "bar"])
    re = Regex::Automata::Hybrid::Regex.builder.build_from_dfas(forward, reverse)

    expect_raises(Exception) { re.pattern_len }
  end

  it "merges successive Thompson options through the underlying DFA builder" do
    builder = Regex::Automata::Hybrid::Regex.builder
      .thompson(Regex::Automata::NFA::NFA.config.utf8(false))
      .thompson(Regex::Automata::NFA::NFA.config.shrink(true))
    re = builder.build("a")

    re.forward.get_nfa.is_utf8.should be_false
    re.reverse.get_nfa.is_utf8.should be_false
  end

  it "ports Rust's fallible newline-quit example" do
    re = Regex::Automata::Hybrid::Regex.builder
      .dfa(Regex::Automata::Hybrid::DFA.config.quit('\n'.ord.to_u8, true))
      .build("foo\\p{any}+bar")
    cache = re.create_cache

    re.try_search(cache, Regex::Automata::Input.new("foo\nbar")).should eq(
      Regex::Automata::MatchError.quit('\n'.ord.to_u8, 3)
    )
    expect_raises(Exception) { re.find(cache, "foo\nbar") }
  end

  it "ports Rust's leftmost-first alternation and non-overlapping iteration examples" do
    re = Regex::Automata::Hybrid::Regex.new("abc|a")
    cache = re.create_cache
    re.find(cache, "abc").should eq(Regex::Automata::Match.must(0, 0...3))

    repeated = Regex::Automata::Hybrid::Regex.new("foo[0-9]+")
    cache = repeated.create_cache
    repeated.find_iter(cache, "foo1 foo12 foo123").to_a.should eq([
      Regex::Automata::Match.must(0, 0...4),
      Regex::Automata::Match.must(0, 5...10),
      Regex::Automata::Match.must(0, 11...17),
    ])
  end

  it "ports Rust's multi-pattern priority example from hybrid::mod" do
    re = Regex::Automata::Hybrid::Regex.new_many(["\\w+", "\\S+"])
    cache = re.create_cache

    re.find_iter(cache, "@foo bar").to_a.should eq([
      Regex::Automata::Match.must(1, 0...4),
      Regex::Automata::Match.must(0, 5...8),
    ])
  end

  it "ports Rust's byte-oriented UTF-8-disabled builder example" do
    re = Regex::Automata::Hybrid::Regex.builder
      .syntax(Regex::Automata::Syntax::Config.new.utf8(false))
      .thompson(Regex::Automata::NFA::NFA.config.utf8(false))
      .build("foo(?-u:[^b])ar.*")
    cache = re.create_cache
    haystack = Bytes[0xFE, 0x66, 0x6F, 0x6F, 0xFF, 0x61, 0x72, 0x7A, 0x7A, 0xE2, 0x98, 0xFF, 0x0A]

    re.find(cache, haystack).should eq(Regex::Automata::Match.must(0, 1...9))
  end

  it "does not overlap adjacent empty matches or split UTF-8 codepoints" do
    re = Regex::Automata::Hybrid::Regex.new("")
    cache = re.create_cache

    re.find_iter(cache, "☃").to_a.should eq([
      Regex::Automata::Match.must(0, 0...0),
      Regex::Automata::Match.must(0, 3...3),
    ])
  end

  it "uses only the forward DFA for existence and anchored or initial-empty matches" do
    re = Regex::Automata::Hybrid::Regex.new("a*")
    cache = re.create_cache
    reverse_usage = cache.reverse.memory_usage

    re.is_match(cache, "aaa").should be_true
    cache.reverse.memory_usage.should eq(reverse_usage)

    re.try_search(cache, Regex::Automata::Input.new("aaa").anchored(Regex::Automata::Anchored::Yes)).should eq(
      Regex::Automata::Match.must(0, 0...3)
    )
    cache.reverse.memory_usage.should eq(reverse_usage)

    re.try_search(cache, Regex::Automata::Input.new("bbb")).should eq(
      Regex::Automata::Match.must(0, 0...0)
    )
    cache.reverse.memory_usage.should eq(reverse_usage)
  end

  it "uses the selected pattern's anchored start without a reverse search" do
    re = Regex::Automata::Hybrid::Regex.builder
      .dfa(Regex::Automata::Hybrid::DFA.config.starts_for_each_pattern(true))
      .build_many(["foo", "bar"])
    cache = re.create_cache
    reverse_usage = cache.reverse.memory_usage
    input = Regex::Automata::Input.new("bar")
      .anchored_pattern(Regex::Automata::PatternID.new(1))

    re.try_search(cache, input).should eq(Regex::Automata::Match.must(1, 0...3))
    cache.reverse.memory_usage.should eq(reverse_usage)
  end

  it "resets both coupled caches and their clear counts" do
    first = Regex::Automata::Hybrid::Regex.new("foo")
    second = Regex::Automata::Hybrid::Regex.new("bar")
    cache = first.create_cache
    forward, reverse = cache.as_parts
    first.find(cache, "xfoo").should eq(Regex::Automata::Match.must(0, 1...4))

    cache.reset(second)
    cache.as_parts[0].same?(forward).should be_true
    cache.as_parts_mut[1].same?(reverse).should be_true
    cache.forward.clear_count.should eq(0_u64)
    cache.reverse.clear_count.should eq(0_u64)
    cache.memory_usage.should eq(cache.forward.memory_usage + cache.reverse.memory_usage)
    second.find(cache, "xbar").should eq(Regex::Automata::Match.must(0, 1...4))
  end

  it "short-circuits existence while the iterator reports a delayed-match quit" do
    re = Regex::Automata::Hybrid::Regex.builder
      .dfa(Regex::Automata::Hybrid::DFA.config.quit('x'.ord.to_u8, true))
      .build("a")
    cache = re.create_cache

    re.is_match(cache, "a x a").should be_true
    matches = re.find_iter(cache, "a x a")
    expect_raises(Exception) { matches.next }
  end

  it "keeps an empty pattern list as a never-matching two-DFA regex" do
    re = Regex::Automata::Hybrid::Regex.new_many([] of String)
    cache = re.create_cache

    re.pattern_len.should eq(0)
    re.is_match(cache, "anything").should be_false
    re.find(cache, "anything").should be_nil
    re.find_iter(cache, "anything").to_a.should be_empty
  end

  it "merges repeated DFA config calls and preserves reverse-only overrides" do
    re = Regex::Automata::Hybrid::Regex.builder
      .dfa(Regex::Automata::Hybrid::DFA.config.quit('x'.ord.to_u8, true))
      .dfa(Regex::Automata::Hybrid::DFA.config.starts_for_each_pattern(true))
      .build_many(["foo", "bar"])

    re.forward.get_config.get_quit('x'.ord.to_u8).should be_true
    re.reverse.get_config.get_quit('x'.ord.to_u8).should be_true
    re.forward.get_config.get_starts_for_each_pattern.should be_true
    re.reverse.get_config.get_starts_for_each_pattern.should be_true
    re.forward.get_match_kind.should eq(Regex::Automata::MatchKind::LeftmostFirst)
    re.reverse.get_match_kind.should eq(Regex::Automata::MatchKind::All)
    re.reverse.get_nfa.is_reverse.should be_true
  end
end
