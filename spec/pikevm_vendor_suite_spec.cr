require "./spec_helper"
require "./support/vendor_regex_suite"

# Pinned oracle: regex-automata/tests/nfa/thompson/pikevm/suite.rs.
# The Rust runner expands compiling fixtures into is_match/find/captures and
# skips overlapping captures and unsupported leftmost-longest match kind.
private def pikevm_vendor_syntax(test : VendorRegexSuite::Case) : Regex::Automata::Syntax::Config
  Regex::Automata::Syntax::Config.new
    .case_insensitive(test.case_insensitive)
    .unicode(test.unicode)
    .utf8(test.utf8)
    .line_terminator(test.line_terminator)
end

private def pikevm_vendor_build(test : VendorRegexSuite::Case, prefilter : Bool) : Regex::Automata::NFA::PikeVM
  syntax = pikevm_vendor_syntax(test)
  kind = test.match_kind == "all" ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst
  config = Regex::Automata::NFA::PikeVM.config.match_kind(kind)
  if prefilter
    hirs = test.patterns.map { |pattern| Regex::Automata::Syntax.parse_with(pattern, syntax) }
    config.prefilter(Regex::Automata::Prefilter.from_hirs_prefix(kind, hirs))
  end
  thompson = Regex::Automata::NFA::NFA.config.utf8(test.utf8)
    .look_matcher(Regex::Automata::LookMatcher.new(test.line_terminator))
  Regex::Automata::NFA::PikeVM.builder
    .configure(config)
    .syntax(syntax)
    .thompson(thompson)
    .build_many(test.patterns)
end

private def pikevm_vendor_input(test : VendorRegexSuite::Case) : Regex::Automata::Input
  Regex::Automata::Input.new(test.haystack)
    .range(test.bounds[0]...test.bounds[1])
    .anchored(test.anchored ? Regex::Automata::Anchored::Yes : Regex::Automata::Anchored::No)
end

private def pikevm_vendor_check(test : VendorRegexSuite::Case, prefilter : Bool) : Nil
  unless test.compiles
    begin
      pikevm_vendor_build(test, prefilter)
    rescue Regex::Automata::BuildError | Regex::Syntax::ParseError
      return
    end
    raise "#{test.full_name} compiled but Rust expects a build error"
  end

  re = pikevm_vendor_build(test, prefilter)
  cache = re.create_cache
  input = pikevm_vendor_input(test)
  expected = test.matches.map { |mat| {mat.id, mat.span[0], mat.span[1]} }
  actual_match = re.is_match(cache, input.clone)
  raise "#{test.full_name} is_match: #{actual_match} != #{!expected.empty?}" unless actual_match == !expected.empty?

  if test.search_kind == "overlapping"
    patset = Regex::Automata::PatternSet.new(re.pattern_len)
    re.which_overlapping_matches(cache, input, patset)
    actual_ids = patset.iter.map(&.to_i).to_a
    raise "#{test.full_name} overlapping: #{actual_ids} != #{test.expected_pattern_ids}" unless actual_ids == test.expected_pattern_ids
    return
  end

  earliest = test.search_kind == "earliest"
  # Bound a broken iterator to two extra results so a non-terminating port
  # produces an assertion instead of exhausting the test host.
  limit = Math.min(test.match_limit || Int32::MAX, expected.size + 2)
  actual = re.find_iter(cache, input.clone.earliest(earliest))
    .first(limit)
    .map { |mat| {mat.pattern.to_i, mat.start, mat.end} }.to_a
  raise "#{test.full_name} find: #{actual} != #{expected}" unless actual == expected

  actual_caps = re.captures_iter(cache, input.clone.earliest(earliest))
    .first(limit)
    .map do |caps|
      {caps.pattern.not_nil!.to_i, (0...caps.group_len).map do |index|
        caps.get_group(index).try { |span| {span.start, span.end} }
      end}
    end.to_a
  expected_caps = test.matches.map { |mat| {mat.id, mat.spans} }
  raise "#{test.full_name} captures: #{actual_caps} != #{expected_caps}" unless actual_caps == expected_caps
end

describe "pinned PikeVM TOML suite" do
  {"default" => false, "prefilter" => true}.each do |mode, use_prefilter|
    VendorRegexSuite.load.groups.each do |group|
      VendorRegexSuite.load.cases(group).each do |test|
        next if test.match_kind == "leftmost-longest"
        it "#{mode}: #{test.full_name} Rust-admissible APIs" do
          pikevm_vendor_check(test, use_prefilter)
        end
      end
    end
  end
end
