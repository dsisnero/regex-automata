require "./spec_helper"
require "./support/vendor_regex_suite"

# Direct port of tests/meta/suite.rs::configure_meta_builder/run_test.
private def meta_vendor_build(test : VendorRegexSuite::Case, mode : String) : Regex::Automata::Meta::Regex
  kind = test.match_kind == "all" ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst
  config = Regex::Automata::Meta::Regex.config.match_kind(kind).utf8_empty(test.utf8).line_terminator(test.line_terminator)
  config = config.dfa(false) unless mode == "default"
  config = config.hybrid(false) if mode.starts_with?("no_dfa_hybrid")
  config = config.onepass(false) if mode.starts_with?("no_dfa_hybrid_onepass")
  config = config.backtrack(false) if mode == "no_dfa_hybrid_onepass_backtrack"
  Regex::Automata::Meta::Regex.builder.configure(config)
    .syntax(Regex::Automata::Syntax::Config.new.case_insensitive(test.case_insensitive)
      .unicode(test.unicode).utf8(test.utf8).line_terminator(test.line_terminator))
    .build_many(test.patterns)
end

private def meta_vendor_check(test : VendorRegexSuite::Case, mode : String) : Nil
  STDERR.puts("meta #{mode}/#{test.full_name}") if ENV["META_SUITE_TRACE"]?
  unless test.compiles
    expect_raises(Regex::Automata::Meta::BuildError) { meta_vendor_build(test, mode) }
    return
  end
  re = meta_vendor_build(test, mode)
  input = Regex::Automata::Input.new(test.haystack).range(test.bounds[0]...test.bounds[1])
    .anchored(test.anchored ? Regex::Automata::Anchored::Yes : Regex::Automata::Anchored::No)
  expected = test.matches.map { |mat| {mat.id, mat.span[0], mat.span[1]} }
  re.is_match(input).should eq(!expected.empty?)
  if test.search_kind == "overlapping"
    patterns = Regex::Automata::PatternSet.new(re.pattern_len)
    re.which_overlapping_matches(input, patterns)
    patterns.iter.map(&.to_i).to_a.should eq(test.expected_pattern_ids)
    return # Rust has no overlapping capture expansion.
  end
  limit = Math.min(test.match_limit || Int32::MAX, expected.size + 2)
  input.earliest(test.search_kind == "earliest")
  actual = re.find_iter(input).first(limit).map { |mat| {mat.pattern.to_i, mat.start, mat.end} }.to_a
  raise "#{mode}/#{test.full_name}: find #{actual} != #{expected}" unless actual == expected
  actual_caps = re.captures_iter(input).first(limit).map do |caps|
    pattern = caps.pattern || raise "missing capture pattern"
    {pattern.to_i, (0...caps.group_len).map { |index| caps.get_group(index).try { |span| {span.start, span.end} } }}
  end.to_a
  expected_caps = test.matches.map { |mat| {mat.id, mat.spans} }
  raise "#{mode}/#{test.full_name}: captures #{actual_caps} != #{expected_caps}" unless actual_caps == expected_caps
end

describe "pinned Meta five-mode TOML suite" do
  %w(default no_dfa no_dfa_hybrid no_dfa_hybrid_onepass no_dfa_hybrid_onepass_backtrack).each do |mode|
    VendorRegexSuite.load.cases.each do |test|
      # Rust applies its blacklist after appending /is_match, /find or
      # /captures, so names ending in "earliest" are also excluded.
      selection_name = test.compiles ? "#{test.full_name}/is_match" : test.full_name
      next if selection_name.includes?("earliest/")
      next if test.match_kind == "leftmost-longest"
      it "#{mode}: #{test.full_name} vendor APIs" do
        meta_vendor_check(test, mode)
      end
    end
  end
end
