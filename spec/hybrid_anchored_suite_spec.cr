require "./spec_helper"
require "./support/vendor_regex_suite"

private record HybridSuiteCase,
  name : String,
  pattern : String,
  haystack : Bytes,
  matches : Array(Tuple(Int32, Int32)),
  bounds : Tuple(Int32, Int32),
  anchored : Bool,
  unicode : Bool,
  utf8 : Bool,
  earliest : Bool,
  match_limit : Int32?,
  match_kind : Regex::Automata::MatchKind

private def hybrid_suite_cases(file : String) : Array(HybridSuiteCase)
  VendorRegexSuite.load.cases(file).map do |fixture|
    HybridSuiteCase.new(
      fixture.name, fixture.patterns[0], fixture.haystack,
      fixture.matches.map(&.span), fixture.bounds, fixture.anchored,
      fixture.unicode, fixture.utf8, fixture.search_kind == "earliest",
      fixture.match_limit,
      fixture.match_kind == "all" ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst
    )
  end
end

private def check_hybrid_suite_case(mode : String, fixture : HybridSuiteCase) : Nil
  config = Regex::Automata::Hybrid::DFA.config
    .match_kind(fixture.match_kind)
    .unicode_word_boundary(true)
  case mode
  when "starts_for_each_pattern" then config.starts_for_each_pattern(true)
  when "specialize_start_states" then config.specialize_start_states(true)
  when "no_byte_classes"         then config.byte_classes(false)
  when "no_cache_clearing"       then config.minimum_cache_clear_count(0)
  when "min_cache_capacity"      then config.cache_capacity(0).skip_cache_capacity_check(true)
  end
  syntax = Regex::Automata::Syntax::Config.new.unicode(fixture.unicode).utf8(fixture.utf8)
  if mode == "prefilter"
    hir = Regex::Automata::Syntax.parse_with(fixture.pattern, syntax)
    config.prefilter(Regex::Automata::Prefilter.from_hir_prefix(fixture.match_kind, hir))
  end
  builder = Regex::Automata::Hybrid::Regex.builder
    .dfa(config)
    .syntax(syntax)
  thompson = Regex::Automata::NFA::NFA.config.utf8(fixture.utf8)
  thompson = thompson.shrink(true) if mode == "nfa_shrink"
  builder.thompson(thompson)
  re = builder.build(fixture.pattern)
  cache = re.create_cache
  input = Regex::Automata::Input.new(fixture.haystack)
    .range(fixture.bounds[0]...fixture.bounds[1])
    .anchored(fixture.anchored ? Regex::Automata::Anchored::Yes : Regex::Automata::Anchored::No)

  re.is_match(cache, input).should eq(!fixture.matches.empty?)
  got = re.find_iter(cache, input.earliest(fixture.earliest)).map do |mat|
    {mat.start, mat.end}
  end.first(fixture.match_limit || Int32::MAX).to_a
  got.should eq(fixture.matches)
end

describe "vendor hybrid anchored suite" do
  cases = hybrid_suite_cases("anchored")
  cases.size.should eq(12)
  modes = %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity)

  modes.each do |mode|
    cases.each do |fixture|
      next if fixture.name == "word-boundary-unicode-01" # Rust skips Unicode word looks on non-ASCII haystacks.

      it "#{mode}: anchored/#{fixture.name} find and is_match" do
        check_hybrid_suite_case(mode, fixture)
      end
    end
  end
end

describe "vendor hybrid empty suite" do
  cases = hybrid_suite_cases("empty")
  cases.size.should eq(19)
  modes = %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity)

  modes.each do |mode|
    cases.each do |fixture|
      it "#{mode}: empty/#{fixture.name} find and is_match" do
        check_hybrid_suite_case(mode, fixture)
      end
    end
  end
end

describe "vendor hybrid CRLF suite" do
  cases = hybrid_suite_cases("crlf")
  cases.size.should eq(15)
  modes = %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity)

  modes.each do |mode|
    cases.each do |fixture|
      it "#{mode}: crlf/#{fixture.name} find and is_match" do
        check_hybrid_suite_case(mode, fixture)
      end
    end
  end
end

describe "vendor hybrid iteration suite" do
  cases = hybrid_suite_cases("iter")
  cases.size.should eq(22)
  modes = %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity)

  modes.each do |mode|
    cases.each do |fixture|
      it "#{mode}: iter/#{fixture.name} find and is_match" do
        check_hybrid_suite_case(mode, fixture)
      end
    end
  end
end

describe "vendor hybrid earliest suite" do
  cases = hybrid_suite_cases("earliest")
  cases.size.should eq(7)
  modes = %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity)

  modes.each do |mode|
    cases.each do |fixture|
      it "#{mode}: earliest/#{fixture.name} find and is_match" do
        check_hybrid_suite_case(mode, fixture)
      end
    end
  end
end

describe "vendor hybrid bounded-substring suite" do
  cases = hybrid_suite_cases("substring")
  cases.size.should eq(4)
  modes = %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity)

  modes.each do |mode|
    cases.each do |fixture|
      # Rust skips Unicode word assertions on non-ASCII haystacks.
      next if fixture.name.starts_with?("unicode-word-")

      it "#{mode}: substring/#{fixture.name} find and is_match" do
        check_hybrid_suite_case(mode, fixture)
      end
    end
  end
end

describe "vendor hybrid inline-flags suite" do
  cases = hybrid_suite_cases("flags")
  cases.size.should eq(11)
  modes = %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity)

  modes.each do |mode|
    cases.each do |fixture|
      it "#{mode}: flags/#{fixture.name} find and is_match" do
        check_hybrid_suite_case(mode, fixture)
      end
    end
  end
end

describe "vendor hybrid multiline suite" do
  cases = hybrid_suite_cases("multiline")
  cases.size.should eq(140)
  modes = %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity)

  modes.each do |mode|
    cases.each do |fixture|
      it "#{mode}: multiline/#{fixture.name} find and is_match" do
        check_hybrid_suite_case(mode, fixture)
      end
    end
  end
end
