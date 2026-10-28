require "./spec_helper"
require "./support/vendor_regex_suite"

# Pinned oracle: regex-automata/tests/nfa/thompson/backtrack/suite.rs.
private def backtrack_vendor_syntax(test : VendorRegexSuite::Case) : Regex::Automata::Syntax::Config
  Regex::Automata::Syntax::Config.new
    .case_insensitive(test.case_insensitive)
    .unicode(test.unicode)
    .utf8(test.utf8)
    .line_terminator(test.line_terminator)
end

private def backtrack_vendor_thompson(test : VendorRegexSuite::Case) : Regex::Automata::HirCompilerConfig
  Regex::Automata::NFA::NFA.config.utf8(test.utf8)
    .look_matcher(Regex::Automata::LookMatcher.new(test.line_terminator))
end

private def backtrack_vendor_build(test : VendorRegexSuite::Case, mode : String) : Regex::Automata::NFA::Backtrack::BoundedBacktracker
  syntax = backtrack_vendor_syntax(test)
  thompson = backtrack_vendor_thompson(test)
  builder = Regex::Automata::NFA::Backtrack::BoundedBacktracker.builder
    .syntax(syntax)
    .thompson(thompson)
  config = Regex::Automata::NFA::Backtrack::BoundedBacktracker.config
  if mode == "prefilter"
    hirs = test.patterns.map { |pattern| Regex::Automata::Syntax.parse_with(pattern, syntax) }
    config.prefilter(Regex::Automata::Prefilter.from_hirs_prefix(Regex::Automata::MatchKind::LeftmostFirst, hirs))
  end
  if mode == "min_visited_capacity"
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(thompson)
      .syntax(syntax)
      .build_many(test.patterns)
    config.visited_capacity(Regex::Automata::NFA::Backtrack.min_visited_capacity(nfa, Regex::Automata::Input.new(test.haystack)))
    return builder.configure(config).build_from_nfa(nfa)
  end
  builder.configure(config).build_many(test.patterns)
end

private def backtrack_vendor_input(test : VendorRegexSuite::Case) : Regex::Automata::Input
  Regex::Automata::Input.new(test.haystack)
    .range(test.bounds[0]...test.bounds[1])
    .anchored(test.anchored ? Regex::Automata::Anchored::Yes : Regex::Automata::Anchored::No)
end

private def backtrack_vendor_check(test : VendorRegexSuite::Case, mode : String) : Nil
  unless test.compiles
    begin
      backtrack_vendor_build(test, mode)
    rescue Regex::Automata::BuildError | Regex::Syntax::ParseError
      return
    end
    raise "#{test.full_name} compiled but Rust expects a build error"
  end

  re = backtrack_vendor_build(test, mode)
  cache = re.create_cache
  input = backtrack_vendor_input(test)
  expected = test.matches.map { |mat| {mat.id, mat.span[0], mat.span[1]} }
  actual_match = re.try_is_match(cache, input.clone)
  raise "#{test.full_name} is_match search error: #{actual_match}" if actual_match.is_a?(Regex::Automata::MatchError)
  raise "#{test.full_name} is_match: #{actual_match} != #{!expected.empty?}" unless actual_match == !expected.empty?

  limit = Math.min(test.match_limit || Int32::MAX, expected.size + 2)
  matches = [] of Tuple(Int32, Int32, Int32)
  match_iter = re.try_find_iter(cache, input.clone)
  limit.times do
    item = match_iter.next
    break if item.nil?
    raise "#{test.full_name} find search error: #{item}" if item.is_a?(Regex::Automata::MatchError)
    matches << {item.pattern.to_i, item.start, item.end}
  end
  raise "#{test.full_name} find: #{matches} != #{expected}" unless matches == expected

  actual_caps = [] of Tuple(Int32, Array(Tuple(Int32, Int32)?))
  capture_iter = re.try_captures_iter(cache, input.clone)
  limit.times do
    item = capture_iter.next
    break if item.nil?
    raise "#{test.full_name} captures search error: #{item}" if item.is_a?(Regex::Automata::MatchError)
    actual_caps << {item.pattern.not_nil!.to_i, (0...item.group_len).map do |index|
      item.get_group(index).try { |span| {span.start, span.end} }
    end}
  end
  expected_caps = test.matches.map { |mat| {mat.id, mat.spans} }
  raise "#{test.full_name} captures: #{actual_caps} != #{expected_caps}" unless actual_caps == expected_caps
end

describe "pinned bounded-backtracker TOML suite" do
  %w(default prefilter min_visited_capacity).each do |mode|
    VendorRegexSuite.load.groups.each do |group|
      VendorRegexSuite.load.cases(group).each do |test|
        next if mode != "min_visited_capacity" && test.full_name.includes?("expensive/backtrack-blow-visited-capacity")
        next unless test.search_kind == "leftmost" && test.match_kind == "leftmost-first"
        it "#{mode}: #{test.full_name} Rust-admissible APIs" do
          backtrack_vendor_check(test, mode)
        end
      end
    end
  end
end
