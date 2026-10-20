require "./spec_helper"
require "./support/vendor_regex_suite"

private record HybridOverlapCase,
  name : String,
  patterns : Array(String),
  haystack : Bytes,
  line_terminator : UInt8,
  compiles : Bool,
  match_limit : Int32?,
  bounds : Tuple(Int32, Int32),
  anchored : Bool,
  utf8 : Bool,
  unicode : Bool,
  case_insensitive : Bool,
  kind : Regex::Automata::MatchKind,
  earliest : Bool,
  overlapping : Bool,
  matches : Array(Tuple(Int32, Int32, Int32))

private def overlap_cases(file : String) : Array(HybridOverlapCase)
  VendorRegexSuite.load.cases(file).map do |fixture|
    HybridOverlapCase.new(
      fixture.name, fixture.patterns, fixture.haystack, fixture.line_terminator,
      fixture.compiles, fixture.match_limit, fixture.bounds, fixture.anchored,
      fixture.utf8, fixture.unicode, fixture.case_insensitive,
      fixture.match_kind == "all" ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst,
      fixture.search_kind == "earliest", fixture.search_kind == "overlapping",
      fixture.matches.map { |mat| {mat.id, mat.span[0], mat.span[1]} }
    )
  end
end

private def hybrid_overlap_matches(fixture : HybridOverlapCase,
                                   mode : String) : Array(Tuple(Int32, Int32, Int32))
  config = Regex::Automata::Hybrid::DFA.config
    .match_kind(fixture.kind)
    .unicode_word_boundary(true)
    .starts_for_each_pattern(fixture.overlapping || mode == "starts_for_each_pattern")
  case mode
  when "specialize_start_states" then config.specialize_start_states(true)
  when "no_byte_classes"         then config.byte_classes(false)
  when "no_cache_clearing"       then config.minimum_cache_clear_count(0)
  when "min_cache_capacity"      then config.cache_capacity(0).skip_cache_capacity_check(true)
  end
  syntax = Regex::Automata::Syntax::Config.new.utf8(fixture.utf8).unicode(fixture.unicode)
    .case_insensitive(fixture.case_insensitive)
    .line_terminator(fixture.line_terminator)
  if mode == "prefilter"
    hirs = fixture.patterns.map { |pattern| Regex::Automata::Syntax.parse_with(pattern, syntax) }
    config.prefilter(Regex::Automata::Prefilter.from_hirs_prefix(fixture.kind, hirs))
  end
  builder = Regex::Automata::Hybrid::Regex.builder.dfa(config).syntax(syntax)
  thompson = Regex::Automata::NFA::NFA.config.utf8(fixture.utf8)
    .look_matcher(Regex::Automata::LookMatcher.new(fixture.line_terminator))
  thompson = thompson.shrink(true) if mode == "nfa_shrink"
  builder.thompson(thompson)
  re = builder.build_many(fixture.patterns)
  cache = re.create_cache
  input = Regex::Automata::Input.new(fixture.haystack)
    .range(fixture.bounds[0]...fixture.bounds[1])
    .anchored(fixture.anchored ? Regex::Automata::Anchored::Yes : Regex::Automata::Anchored::No)
  re.is_match(cache, input.clone.earliest(true)).should eq(!fixture.matches.empty?)
  unless fixture.overlapping
    return re.find_iter(cache, input.clone.earliest(fixture.earliest)).first(fixture.match_limit || Int32::MAX)
      .map { |mat| {mat.pattern.to_i, mat.start, mat.end} }.to_a
  end
  patset = Regex::Automata::PatternSet.new(re.pattern_len)
  re.forward.try_which_overlapping_matches(cache.forward, input, patset).should be_nil
  patset.iter.map(&.to_i).to_a.should eq(fixture.matches.map(&.[0]).uniq.sort)
  fwd_state = Regex::Automata::Hybrid::OverlappingState.start
  got = [] of Tuple(Int32, Int32, Int32)
  loop do
    re.forward.try_search_overlapping_fwd(cache.forward, input, fwd_state)
    ending = fwd_state.get_match
    break unless ending
    reverse_input = input.clone
      .range(input.start...ending.offset)
      .anchored(Regex::Automata::Anchored::Pattern, ending.pattern)
      .earliest(false)
    rev_state = Regex::Automata::Hybrid::OverlappingState.start
    loop do
      re.reverse.try_search_overlapping_rev(cache.reverse, reverse_input, rev_state)
      starting = rev_state.get_match
      break unless starting
      got << {ending.pattern.to_i, starting.offset, ending.offset}
    end
  end
  got
end

private def hybrid_suite_supported?(fixture : HybridOverlapCase) : Bool
  return true unless fixture.compiles

  haystack = fixture.haystack
  bytes = haystack.is_a?(String) ? haystack.to_slice : haystack
  return true unless bytes.any? { |byte| byte >= 0x80_u8 }

  syntax = Regex::Automata::Syntax::Config.new.utf8(fixture.utf8).unicode(fixture.unicode)
    .case_insensitive(fixture.case_insensitive)
    .line_terminator(fixture.line_terminator)
  fixture.patterns.none? do |pattern|
    Regex::Automata::Syntax.parse_with(pattern, syntax).properties.look_set.contains_word_unicode
  end
end

describe "vendor hybrid overlapping suite" do
  cases = overlap_cases("overlapping")
  cases.size.should eq(23)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      it "#{mode}: overlapping/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid multi-pattern set suite" do
  cases = overlap_cases("set")
  cases.size.should eq(52)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      it "#{mode}: set/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid leftmost-all suite" do
  cases = overlap_cases("leftmost-all")
  cases.size.should eq(3)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      it "#{mode}: leftmost-all/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid binary-byte suite" do
  cases = overlap_cases("bytes")
  cases.size.should eq(26)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      # Rust skips Unicode word assertions on non-ASCII haystacks.
      next if fixture.name.in?("word-boundary-unicode", "word-boundary-unicode-not")

      it "#{mode}: bytes/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid UTF-8 boundary suite" do
  cases = overlap_cases("utf8")
  cases.size.should eq(28)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      it "#{mode}: utf8/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid custom line terminator suite" do
  cases = overlap_cases("line-terminator")
  cases.size.should eq(10)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      it "#{mode}: line-terminator/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid no-Unicode suite" do
  cases = overlap_cases("no-unicode")
  cases.size.should eq(23)
  cases.count { |fixture| hybrid_suite_supported?(fixture) }.should eq(23)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      next unless hybrid_suite_supported?(fixture)

      it "#{mode}: no-unicode/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid Unicode suite" do
  cases = overlap_cases("unicode")
  cases.size.should eq(84)
  # Rust excludes Unicode word assertions on non-ASCII haystacks.
  cases.reject { |fixture| hybrid_suite_supported?(fixture) }.map(&.name)
    .should eq(%w(wb-100 wb-200 wb-300 wb-400))
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      next unless hybrid_suite_supported?(fixture)

      it "#{mode}: unicode/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid word-boundary suite" do
  cases = overlap_cases("word-boundary")
  cases.size.should eq(103)
  cases.count { |fixture| hybrid_suite_supported?(fixture) }.should eq(95)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      next unless hybrid_suite_supported?(fixture)

      it "#{mode}: word-boundary/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid special word-boundary suite" do
  cases = overlap_cases("word-boundary-special")
  cases.size.should eq(92)
  cases.count { |fixture| hybrid_suite_supported?(fixture) }.should eq(68)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      next unless hybrid_suite_supported?(fixture)

      it "#{mode}: word-boundary-special/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid regression suite" do
  cases = overlap_cases("regression")
  cases.size.should eq(105)
  cases.count { |fixture| hybrid_suite_supported?(fixture) }.should eq(100)
  cases.count { |fixture| !fixture.compiles }.should eq(5)
  cases.find { |fixture| fixture.name == "i969" }.not_nil!.earliest.should be_true
  cases.find { |fixture| fixture.name == "reverse-suffix-all-no-early-matches-010" }.not_nil!.kind
    .should eq(Regex::Automata::MatchKind::All)
  cases.find { |fixture| fixture.name == "fowler-basic154-unanchored" }.not_nil!.patterns
    .should eq(["a([bc]*)c*"])
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      next unless hybrid_suite_supported?(fixture)

      it "#{mode}: regression/#{fixture.name}" do
        if fixture.compiles
          hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
        elsif mode == "prefilter"
          expect_raises(Regex::Syntax::Error) { hybrid_overlap_matches(fixture, mode) }
        else
          expect_raises(Regex::Automata::Hybrid::BuildError) { hybrid_overlap_matches(fixture, mode) }
        end
      end
    end
  end
end

describe "vendor hybrid crazy suite" do
  cases = overlap_cases("crazy")
  cases.size.should eq(52)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      it "#{mode}: crazy/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid miscellaneous suite" do
  cases = overlap_cases("misc")
  cases.size.should eq(16)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      it "#{mode}: misc/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid expensive suite" do
  cases = overlap_cases("expensive")
  cases.map(&.name).should eq(%w(regression-many-repeat-no-stack-overflow backtrack-blow-visited-capacity))
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      # Rust blacklists this test outside the shrink/minimum-capacity modes.
      next if fixture.name == "regression-many-repeat-no-stack-overflow" && !mode.in?("nfa_shrink", "min_cache_capacity")

      it "#{mode}: expensive/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid Fowler basic suite" do
  cases = overlap_cases("fowler/basic")
  cases.size.should eq(204)
  cases.count { |fixture| hybrid_suite_supported?(fixture) }.should eq(204)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      next unless hybrid_suite_supported?(fixture)

      it "#{mode}: fowler/basic/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid Fowler null-subexpression suite" do
  cases = overlap_cases("fowler/nullsubexpr")
  cases.size.should eq(50)
  cases.count { |fixture| hybrid_suite_supported?(fixture) }.should eq(50)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      next unless hybrid_suite_supported?(fixture)

      it "#{mode}: fowler/nullsubexpr/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end

describe "vendor hybrid Fowler repetition suite" do
  cases = overlap_cases("fowler/repetition")
  cases.size.should eq(91)
  cases.count { |fixture| hybrid_suite_supported?(fixture) }.should eq(91)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      next unless hybrid_suite_supported?(fixture)

      it "#{mode}: fowler/repetition/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end
