require "./spec_helper"
require "./support/vendor_regex_suite"

private def onepass_vendor_build(test : VendorRegexSuite::Case, mode : String) : Regex::Automata::DFA::OnePass::DFA
  kind = test.match_kind == "all" ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst
  Regex::Automata::DFA::OnePass::DFA.builder
    .configure(Regex::Automata::DFA::OnePass::DFA.config.match_kind(kind)
      .byte_classes(mode != "no_byte_classes").starts_for_each_pattern(mode == "starts_for_each_pattern"))
    .syntax(Regex::Automata::Syntax::Config.new.case_insensitive(test.case_insensitive)
      .unicode(test.unicode).utf8(test.utf8).line_terminator(test.line_terminator))
    .thompson(Regex::Automata::NFA::NFA.config.utf8(test.utf8)
      .look_matcher(Regex::Automata::LookMatcher.new(test.line_terminator)))
    .build_many(test.patterns)
end

private def onepass_vendor_check(test : VendorRegexSuite::Case, mode : String, oracle : Array(String)) : Nil
  STDERR.puts("onepass #{mode}/#{test.full_name}") if ENV["ONEPASS_SUITE_TRACE"]?
  if oracle[2] == "err"
    error = expect_raises(Regex::Automata::DFA::OnePass::BuildError) { onepass_vendor_build(test, mode) }
    error.kind.should eq(Regex::Automata::DFA::OnePass::BuildError::Kind::NotOnePass)
    return
  end
  re = onepass_vendor_build(test, mode)
  re.state_len.should eq(oracle[3].to_i)
  re.alphabet_len.should eq(oracle[4].to_i)
  re.stride.should eq(oracle[5].to_i)
  re.memory_usage.should eq(oracle[6].to_i64)
  cache = re.create_cache
  input = Regex::Automata::Input.new(test.haystack).range(test.bounds[0]...test.bounds[1])
    .anchored(Regex::Automata::Anchored::Yes)
  expected = test.matches.map { |mat| {mat.id, mat.span[0], mat.span[1]} }
  re.is_match(cache, input.clone.earliest(true)).should eq(!expected.empty?)
  return if test.search_kind == "overlapping" # Rust supports only the is_match expansion.

  limit = Math.min(test.match_limit || Int32::MAX, expected.size + 2)
  input.earliest(test.search_kind == "earliest")
  caps = re.create_captures
  actual = Regex::Automata::Searcher.new(input).into_matches_iter do |current|
    result = re.try_search(cache, current, caps)
    result.is_a?(Regex::Automata::MatchError) ? result : caps.get_match
  end.infallible.first(limit).map { |mat| {mat.pattern.to_i, mat.start, mat.end} }.to_a
  raise "#{mode}/#{test.full_name}: find #{actual} != #{expected}" unless actual == expected
  actual_caps = Regex::Automata::Searcher.new(input).into_captures_iter(re.create_captures) do |current, captures|
    re.try_search(cache, current, captures)
  end.infallible.first(limit).map do |captures|
    pattern = captures.pattern || raise "missing matched pattern"
    {pattern.to_i, (0...captures.group_len).map { |index| captures.get_group(index).try { |span| {span.start, span.end} } }}
  end.to_a
  expected_caps = test.matches.map { |mat| {mat.id, mat.spans} }
  raise "#{mode}/#{test.full_name}: captures #{actual_caps} != #{expected_caps}" unless actual_caps == expected_caps

  # Same admitted case IDs and Input are also checked through another engine.
  kind = test.match_kind == "all" ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst
  pike = Regex::Automata::NFA::PikeVM.builder
    .configure(Regex::Automata::NFA::PikeVM.config.match_kind(kind))
    .build_from_nfa(re.get_nfa)
  differential = pike.find_iter(pike.create_cache, input).first(limit)
    .map { |mat| {mat.pattern.to_i, mat.start, mat.end} }.to_a
  raise "#{mode}/#{test.full_name}: PikeVM #{differential} != #{actual}" unless differential == actual
end

describe "pinned one-pass full anchored TOML suite" do
  rows = File.read(File.join(__DIR__, "fixtures", "onepass_suite.tsv")).lines.reject(&.starts_with?("#"))
    .map(&.split('\t'))
  %w(default no_byte_classes starts_for_each_pattern).each do |mode|
    cases = VendorRegexSuite.load.cases.select { |test| test.anchored && test.match_kind != "leftmost-longest" }
    it "#{mode}: preserves exact Rust selection and admission counts" do
      cases.size.should eq(328)
      selected = rows.select { |row| row[0] == mode }
      selected.size.should eq(328)
      selected.count { |row| row[2] == "ok" }.should eq(120)
      selected.count { |row| row[2] == "err" }.should eq(208)
      selected.map(&.[1]).sort.should eq(cases.map(&.full_name).sort)
    end
    by_name = rows.select { |row| row[0] == mode }.to_h { |row| {row[1], row} }
    cases.each do |test|
      it "#{mode}: #{test.full_name} admission, shape, is_match/find/captures" do
        onepass_vendor_check(test, mode, by_name[test.full_name])
      end
    end
  end
end
