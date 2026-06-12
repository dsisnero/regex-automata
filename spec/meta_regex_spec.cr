require "./spec_helper"

private def large_literal_alternation(count : Int32) : String
  Array.new(count) { |i| "tok#{i.to_s.rjust(4, '0')}" }.join("|")
end

describe Regex::Automata::Meta::Regex do
  it "default" do
    re = Regex::Automata::Meta::Regex.builder.build_many(["foo[0-9]+", "bar"] of String)

    re.is_match("zzzfoo123zzz").should be_true
    re.find("zzzfoo123zzz").should eq(Regex::Automata::Match.must(0, 3...9))

    caps = re.create_captures
    re.captures("bar", caps)
    caps.get_match.should eq(Regex::Automata::Match.must(1, 0...3))
  end

  it "no_dfa" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false))
      .build("foo|bar")

    re.find("zzbarzz").should eq(Regex::Automata::Match.must(0, 2...5))
  end

  it "no_dfa_hybrid" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(
        Regex::Automata::Meta::Regex.config
          .dfa(false)
          .hybrid(false)
      )
      .build("[a-z]+")

    re.find("123abc456").should eq(Regex::Automata::Match.must(0, 3...6))
  end

  it "no_dfa_hybrid_onepass" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(
        Regex::Automata::Meta::Regex.config
          .dfa(false)
          .hybrid(false)
          .onepass(false)
      )
      .build("sam|samwise")

    re.find("samwise").should eq(Regex::Automata::Match.must(0, 0...3))
  end

  it "no_dfa_hybrid_onepass_backtrack" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(
        Regex::Automata::Meta::Regex.config
          .dfa(false)
          .hybrid(false)
          .onepass(false)
          .backtrack(false)
      )
      .build("foo\\d+")

    re.is_match("foo123").should be_true
    re.find("foo123").should eq(Regex::Automata::Match.must(0, 0...6))
  end

  it "reports the pattern that caused a syntax error" do
    expect_raises(Regex::Automata::Meta::BuildError) do
      Regex::Automata::Meta::Regex.builder.build_many(["a", "\\p{Foo}", "c"] of String)
    end.tap do |error|
      error.pattern.should eq(Regex::Automata::PatternID.new(1))
      error.syntax_error.should_not be_nil
      error.message.should eq("error parsing pattern 1")
    end
  end

  it "supports explicit cache-backed searching" do
    re = Regex::Automata::Meta::Regex.new("foo(?P<num>[0-9]+)")
    cache = re.create_cache
    input = Regex::Automata::Input.new("xxfoo123yy")

    re.search_with(cache, input).should eq(Regex::Automata::Match.must(0, 2...8))
    re.search_half_with(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 8))

    caps = re.create_captures
    re.search_captures_with(cache, input, caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 2...8))
    caps.get_group_by_name("num").should eq(Regex::Automata::Span.new(5, 8))
  end

  it "uses the literal fast path for exact single-pattern languages" do
    re = Regex::Automata::Meta::Regex.new("sam|samwise")
    cache = re.create_cache
    caps = re.create_captures
    int_slots = Array(Int32?).new(caps.slot_len, nil)
    nm_slots = Array(Regex::Automata::NonMaxUsize?).new(caps.slot_len, nil)

    re.is_accelerated.should be_true
    re.find("samwise").should eq(Regex::Automata::Match.must(0, 0...3))
    re.search_half_with(cache, Regex::Automata::Input.new("samwise")).should eq(
      Regex::Automata::HalfMatch.must(0, 3)
    )
    re.search_captures_with(cache, Regex::Automata::Input.new("xxsamyy"), caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 2...5))
    re.search_slots_with(cache, Regex::Automata::Input.new("xxsamyy"), int_slots).should eq(
      Regex::Automata::PatternID.new(0)
    )
    int_slots.should eq([2, 5])
    re.search_slots_with(cache, Regex::Automata::Input.new("xxsamyy"), nm_slots).should eq(
      Regex::Automata::PatternID.new(0)
    )
    nm_slots.map(&.try(&.get)).should eq([2, 5])
  end

  it "matches the vendor acceleration signal for simple literals" do
    Regex::Automata::Meta::Regex.new("foo").is_accelerated.should be_true
    Regex::Automata::Meta::Regex.new("\\w").is_accelerated.should be_false
  end

  it "uses the large alternation literal bypass when heuristic extraction gives up" do
    pattern = large_literal_alternation(1000)
    re = Regex::Automata::Meta::Regex.new(pattern)
    cache = re.create_cache
    input = Regex::Automata::Input.new("xxtok0777yy")
    slots = [nil, nil] of Int32?

    re.is_accelerated.should be_true
    re.memory_usage.should be > re.pikevm.memory_usage
    re.search_with(cache, input).should eq(Regex::Automata::Match.must(0, 2...9))
    re.search_half_with(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 9))
    re.search_slots_with(cache, input, slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([2, 9])
  end

  it "disables the large alternation literal bypass when auto prefilters are off" do
    pattern = large_literal_alternation(1000)
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.auto_prefilter(false))
      .build(pattern)

    re.is_accelerated.should be_false
    re.find("xxtok0777yy").should eq(Regex::Automata::Match.must(0, 2...9))
  end

  it "uses the literal fast path for exact multi-pattern literal sets" do
    re = Regex::Automata::Meta::Regex.builder.build_many(["foo", "bar", "foobar"] of String)
    cache = re.create_cache
    caps = re.create_captures
    slots = Array(Int32?).new(caps.slot_len, nil)
    patset = Regex::Automata::PatternSet.new(re.pattern_len)

    re.is_accelerated.should be_true
    re.search_with(cache, Regex::Automata::Input.new("xxbaryy")).should eq(
      Regex::Automata::Match.must(1, 2...5)
    )
    re.search_half_with(cache, Regex::Automata::Input.new("xxbaryy")).should eq(
      Regex::Automata::HalfMatch.must(1, 5)
    )
    re.search_captures_with(cache, Regex::Automata::Input.new("xxbaryy"), caps)
    caps.get_match.should eq(Regex::Automata::Match.must(1, 2...5))
    re.search_slots_with(cache, Regex::Automata::Input.new("xxbaryy"), slots).should eq(
      Regex::Automata::PatternID.new(1)
    )
    slots.should eq([nil, nil, 2, 5, nil, nil])

    re.search_with(
      cache,
      Regex::Automata::Input.new("foobar").anchored(
        Regex::Automata::Anchored::Pattern,
        Regex::Automata::PatternID.new(2)
      )
    ).should eq(Regex::Automata::Match.must(2, 0...6))

    re.which_overlapping_matches_with(
      cache,
      Regex::Automata::Input.new("xxfoobar").span(2...8).anchored(Regex::Automata::Anchored::Yes),
      patset
    )
    patset.contains(Regex::Automata::PatternID.new(0)).should be_true
    patset.contains(Regex::Automata::PatternID.new(1)).should be_false
    patset.contains(Regex::Automata::PatternID.new(2)).should be_true
  end

  it "uses automatic core prefilters for non-literal meta regexes" do
    re = Regex::Automata::Meta::Regex.new("Bruce \\w+")

    re.is_accelerated.should be_true
    re.memory_usage.should be > re.pikevm.memory_usage
    re.find("xxBruce Wayne!").should eq(Regex::Automata::Match.must(0, 2...13))
  end

  it "disables automatic core prefilters when configured" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.auto_prefilter(false))
      .build("Bruce \\w+")

    re.is_accelerated.should be_false
    re.find("xxBruce Wayne!").should eq(Regex::Automata::Match.must(0, 2...13))
  end

  it "lets explicit core prefilters drive acceleration" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["Bruce "]
    )
    re = Regex::Automata::Meta::Regex.builder
      .configure(
        Regex::Automata::Meta::Regex.config
          .auto_prefilter(false)
          .prefilter(pre)
      )
      .build("Bruce \\w+")

    re.is_accelerated.should be_true
    re.find("xxBruce Wayne!").should eq(Regex::Automata::Match.must(0, 2...13))
  end

  it "uses reverse anchored acceleration for end-anchored regexes" do
    re = Regex::Automata::Meta::Regex.new("foo$")
    cache = re.create_cache
    input = Regex::Automata::Input.new("xxfoo")
    slots = [nil, nil] of Int32?

    re.is_accelerated.should be_true
    re.memory_usage.should be > re.pikevm.memory_usage
    re.search_with(cache, input).should eq(Regex::Automata::Match.must(0, 2...5))
    re.search_half_with(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 5))
    re.search_slots_with(cache, input, slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([2, 5])
  end

  it "reruns capture searches after reverse anchored start discovery" do
    re = Regex::Automata::Meta::Regex.new("(?P<word>foo)$")
    cache = re.create_cache
    caps = re.create_captures
    slots = Array(Int32?).new(caps.slot_len, nil)
    input = Regex::Automata::Input.new("xxfoo")

    re.search_captures_with(cache, input, caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 2...5))
    caps.get_group_by_name("word").should eq(Regex::Automata::Span.new(2, 5))
    re.search_slots_with(cache, input, slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([2, 5, 2, 5])
  end

  it "does not use reverse anchored acceleration when also anchored at the start" do
    re = Regex::Automata::Meta::Regex.new("^foo$")
    input = Regex::Automata::Input.new("xxfoo").anchored(Regex::Automata::Anchored::Yes)

    re.is_accelerated.should be_false
    re.find(input).should be_nil
  end

  it "treats end-anchored regexes as impossible before the haystack end" do
    re = Regex::Automata::Meta::Regex.new("foo$")
    input = Regex::Automata::Input.new("xxfoo!").span(0...5)

    re.find(input).should be_nil
  end

  it "uses reverse suffix acceleration for greedy suffix matches" do
    re = Regex::Automata::Meta::Regex.new("[a-z]+ing")
    cache = re.create_cache
    input = Regex::Automata::Input.new("tingling")
    slots = [nil, nil] of Int32?

    re.is_accelerated.should be_true
    re.search_with(cache, input).should eq(Regex::Automata::Match.must(0, 0...8))
    re.search_half_with(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 8))
    re.search_slots_with(cache, input, slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 8])
  end

  it "reruns explicit captures after reverse suffix start discovery" do
    re = Regex::Automata::Meta::Regex.new("(?P<word>[a-z]+)ing")
    cache = re.create_cache
    caps = re.create_captures
    slots = Array(Int32?).new(caps.slot_len, nil)
    input = Regex::Automata::Input.new("tingling")

    re.search_captures_with(cache, input, caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 0...8))
    caps.get_group_by_name("word").should eq(Regex::Automata::Span.new(0, 5))
    re.search_slots_with(cache, input, slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 8, 0, 5])
  end

  it "uses reverse inner acceleration for inner literal matches" do
    re = Regex::Automata::Meta::Regex.new("[a-z]+XYZ\\d+")
    cache = re.create_cache
    input = Regex::Automata::Input.new("abcXYZ123")
    slots = [nil, nil] of Int32?

    re.is_accelerated.should be_true
    re.search_with(cache, input).should eq(Regex::Automata::Match.must(0, 0...9))
    re.search_half_with(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 9))
    re.search_slots_with(cache, input, slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 9])
  end

  it "reruns explicit captures after reverse inner start discovery" do
    re = Regex::Automata::Meta::Regex.new("(?P<word>[a-z]+)XYZ\\d+")
    cache = re.create_cache
    caps = re.create_captures
    slots = Array(Int32?).new(caps.slot_len, nil)
    input = Regex::Automata::Input.new("abcXYZ123")

    re.search_captures_with(cache, input, caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 0...9))
    caps.get_group_by_name("word").should eq(Regex::Automata::Span.new(0, 3))
    re.search_slots_with(cache, input, slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 9, 0, 3])
  end

  it "continues reverse inner search after a failed forward confirmation" do
    re = Regex::Automata::Meta::Regex.new("\\d+XYZ\\d+")
    cache = re.create_cache
    input = Regex::Automata::Input.new("123XYZabc999XYZ456")

    re.search_with(cache, input).should eq(Regex::Automata::Match.must(0, 9...18))
    re.search_half_with(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 18))
  end

  it "does not use reverse inner acceleration when always anchored at the start" do
    re = Regex::Automata::Meta::Regex.new("^[a-z]+XYZ\\d+")
    input = Regex::Automata::Input.new("!!abcXYZ123").anchored(Regex::Automata::Anchored::Yes)

    re.is_accelerated.should be_false
    re.find(input).should be_nil
  end

  it "supports overlapping pattern discovery under MatchKind::All" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.match_kind(Regex::Automata::MatchKind::All))
      .build_many(["\\w+", "\\d+", "foo", "bar", "foobar"] of String)

    patset = Regex::Automata::PatternSet.new(re.pattern_len)
    re.which_overlapping_matches(Regex::Automata::Input.new("foobar"), patset)

    patset.iter.to_a.should eq([
      Regex::Automata::PatternID.new(0),
      Regex::Automata::PatternID.new(2),
      Regex::Automata::PatternID.new(3),
      Regex::Automata::PatternID.new(4),
    ])
  end

  it "preserves existing overlapping pattern ids on impossible inputs" do
    re = Regex::Automata::Meta::Regex.new("^foo$")
    patset = Regex::Automata::PatternSet.new(re.pattern_len)
    patset.insert(Regex::Automata::PatternID.new(0))

    re.which_overlapping_matches(Regex::Automata::Input.new("xxfoo").span(1...5), patset)

    patset.iter.to_a.should eq([Regex::Automata::PatternID.new(0)])
  end

  it "accumulates literal overlapping matches without clearing the pattern set" do
    re = Regex::Automata::Meta::Regex.builder.build_many(["foo", "foobar"] of String)
    cache = re.create_cache
    patset = Regex::Automata::PatternSet.new(re.pattern_len + 1)
    patset.insert(Regex::Automata::PatternID.new(2))

    re.which_overlapping_matches_with(
      cache,
      Regex::Automata::Input.new("xxfoobar").span(2...8).anchored(Regex::Automata::Anchored::Yes),
      patset
    )

    patset.iter.to_a.should eq([
      Regex::Automata::PatternID.new(0),
      Regex::Automata::PatternID.new(1),
      Regex::Automata::PatternID.new(2),
    ])
  end

  it "honors utf8_empty(false) for empty matches inside a codepoint" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.utf8_empty(false))
      .build("a*")

    input = Regex::Automata::Input.new("☃").span(1...2)
    re.is_match(input).should be_true
    re.find(input).should eq(Regex::Automata::Match.must(0, 1...1))
  end

  it "uses the configured line terminator with syntax settings" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.line_terminator(0_u8))
      .syntax(Regex::Automata::Syntax::Config.new.multi_line(true))
      .build("^foo$")

    re.find("\x00foo\x00").should eq(Regex::Automata::Match.must(0, 1...4))
  end

  it "ignores builder syntax settings when building from hir" do
    hir = Regex::Syntax::Hir::Hir.dot(Regex::Syntax::Hir::Dot::AnyChar)
    re = Regex::Automata::Meta::Regex.builder
      .syntax(Regex::Automata::Syntax::Config.new.utf8(false))
      .build_from_hir(hir)

    re.nfa.is_utf8.should be_true
    re.find("☃").should eq(Regex::Automata::Match.must(0, 0...3))
  end

  it "builds many regexes directly from hir" do
    hir1 = Regex::Syntax::Hir::Hir.concat([
      Regex::Syntax::Hir::Hir.look(Regex::Syntax::Hir::Look::Kind::StartCRLF),
      Regex::Syntax::Hir::Hir.literal("foo".to_slice),
      Regex::Syntax::Hir::Hir.look(Regex::Syntax::Hir::Look::Kind::EndCRLF),
    ])
    hir2 = Regex::Syntax::Hir::Hir.concat([
      Regex::Syntax::Hir::Hir.look(Regex::Syntax::Hir::Look::Kind::StartCRLF),
      Regex::Syntax::Hir::Hir.literal("bar".to_slice),
      Regex::Syntax::Hir::Hir.look(Regex::Syntax::Hir::Look::Kind::EndCRLF),
    ])
    re = Regex::Automata::Meta::Regex.builder.build_many_from_hir([hir1, hir2])

    re.find_iter("\r\nfoo\r\nbar").to_a.should eq([
      Regex::Automata::Match.must(0, 2...5),
      Regex::Automata::Match.must(1, 7...10),
    ])
  end

  it "treats zero patterns as a regex that never matches" do
    re = Regex::Automata::Meta::Regex.builder.build_many([] of String)

    re.pattern_len.should eq(0)
    re.find("").should be_nil
  end

  it "reports vendor capture counts for single patterns" do
    len = ->(pattern : String) { Regex::Automata::Meta::Regex.new(pattern).captures_len }

    len.call("a").should eq(1)
    len.call("(a)").should eq(2)
    len.call("(a)|(b)").should eq(3)
    len.call("(a)(b)|(c)(d)").should eq(5)
    len.call("(a)|b").should eq(2)
    len.call("a|(b)").should eq(2)
    len.call("(b)*").should eq(2)
    len.call("(b)+").should eq(2)
  end

  it "reports vendor capture counts for multiple patterns" do
    len = ->(patterns : Array(String)) { Regex::Automata::Meta::Regex.new_many(patterns).captures_len }

    len.call(["a", "b"] of String).should eq(2)
    len.call(["(a)", "(b)"] of String).should eq(4)
    len.call(["(a)|(b)", "(c)|(d)"] of String).should eq(6)
    len.call(["(a)(b)|(c)(d)", "(x)(y)"] of String).should eq(8)
    len.call(["(a)", "b"] of String).should eq(3)
    len.call(["a", "(b)"] of String).should eq(3)
    len.call(["(a)", "(b)*"] of String).should eq(4)
    len.call(["(a)+", "(b)+"] of String).should eq(4)
  end

  it "reports vendor static capture counts for single patterns" do
    len = ->(pattern : String) { Regex::Automata::Meta::Regex.new(pattern).static_captures_len }

    len.call("a").should eq(1)
    len.call("(a)").should eq(2)
    len.call("(a)|(b)").should eq(2)
    len.call("(a)(b)|(c)(d)").should eq(3)
    len.call("(a)|b").should be_nil
    len.call("a|(b)").should be_nil
    len.call("(b)*").should be_nil
    len.call("(b)+").should eq(2)
  end

  it "reports vendor static capture counts for multiple patterns" do
    len = ->(patterns : Array(String)) { Regex::Automata::Meta::Regex.new_many(patterns).static_captures_len }

    len.call(["a", "b"] of String).should eq(1)
    len.call(["(a)", "(b)"] of String).should eq(2)
    len.call(["(a)|(b)", "(c)|(d)"] of String).should eq(2)
    len.call(["(a)(b)|(c)(d)", "(x)(y)"] of String).should eq(3)
    len.call(["(a)", "b"] of String).should be_nil
    len.call(["a", "(b)"] of String).should be_nil
    len.call(["(a)", "(b)*"] of String).should be_nil
    len.call(["(a)+", "(b)+"] of String).should eq(2)
  end

  it "iterates captures and split spans" do
    re = Regex::Automata::Meta::Regex.new("foo(?P<num>[0-9]+)")

    re.captures_iter("foo1 foo12").map(&.get_group_by_name("num")).to_a.should eq([
      Regex::Automata::Span.new(3, 4),
      Regex::Automata::Span.new(8, 10),
    ])

    splitter = Regex::Automata::Meta::Regex.new("[ ]+")
    splitter.split("a b  c").to_a.should eq([
      Regex::Automata::Span.new(0, 1),
      Regex::Automata::Span.new(2, 3),
      Regex::Automata::Span.new(5, 6),
    ])
  end

  it "counts one match for suffix literal regressions" do
    re = Regex::Automata::Meta::Regex.new("[a-zA-Z]+ing")

    re.find_iter("tingling").to_a.size.should eq(1)
  end
end
