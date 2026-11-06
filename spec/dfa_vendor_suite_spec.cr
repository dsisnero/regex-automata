require "./spec_helper"
require "./support/vendor_regex_suite"

# Pinned oracle: regex-automata/tests/dfa/suite.rs::compiler/run_test.
private def dense_vendor_build(test : VendorRegexSuite::Case, mode : String) : Regex::Automata::DFA::Regex
  kind = test.match_kind == "all" ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst
  config = Regex::Automata::DFA::DFA.config
    .start_kind(test.anchored ? Regex::Automata::StartKind::Anchored : Regex::Automata::StartKind::Unanchored)
    .match_kind(kind)
    .unicode_word_boundary(true)
  config.starts_for_each_pattern(true) if test.search_kind == "overlapping"
  config.specialize_start_states(true) if mode == "specialized_start_states"
  config.byte_classes(false) if mode == "no_byte_class" || mode == "minimized_no_byte_class"
  config.minimize(true) if mode == "minimized_default" || mode == "minimized_no_byte_class"
  if mode == "prefilter"
    syntax = Regex::Automata::Syntax::Config.new
      .case_insensitive(test.case_insensitive)
      .unicode(test.unicode)
      .utf8(test.utf8)
      .line_terminator(test.line_terminator)
    hirs = test.patterns.map { |pattern| Regex::Automata::Syntax.parse_with(pattern, syntax) }
    config.prefilter(Regex::Automata::Prefilter.from_hirs_prefix(kind, hirs))
  end
  Regex::Automata::DFA::Regex.builder
    .dense(config)
    .syntax { |parser| parser.case_insensitive(test.case_insensitive).unicode(test.unicode).utf8(test.utf8).line_terminator(test.line_terminator) }
    .thompson do |compiler|
      configured = compiler.utf8(test.utf8).look_matcher(Regex::Automata::LookMatcher.new(test.line_terminator))
      configured = configured.shrink(true) if mode == "nfa_shrink"
      configured
    end
    .build_many(test.patterns)
end

private def dense_vendor_check(test : VendorRegexSuite::Case, mode : String) : Nil
  return if test.full_name.includes?("expensive") # regex-test TestRunner::blacklist is a substring rule.
  return if test.match_kind == "leftmost-longest"
  STDERR.puts("dense suite #{mode}/#{test.full_name}") if ENV["DENSE_SUITE_TRACE"]?

  syntax = Regex::Automata::Syntax::Config.new
    .case_insensitive(test.case_insensitive)
    .unicode(test.unicode)
    .utf8(test.utf8)
    .line_terminator(test.line_terminator)
  if test.haystack.any? { |byte| byte >= 0x80_u8 }
    hirs = test.patterns.map { |pattern| Regex::Automata::Syntax.parse_with(pattern, syntax) }
    return if hirs.any?(&.properties.look_set.contains_word_unicode)
  end

  unless test.compiles
    begin
      dense_vendor_build(test, mode)
    rescue Regex::Automata::BuildError | Regex::Syntax::ParseError
      return
    end
    raise "#{mode}: #{test.full_name} compiled but Rust expects a build error"
  end

  re = dense_vendor_build(test, mode)
  if mode == "serialization"
    forward = Regex::Automata::DFA::DFA.from_bytes(re.forward.to_bytes_native_endian[0])[0]
    reverse = Regex::Automata::DFA::DFA.from_bytes(re.reverse.to_bytes_native_endian[0])[0]
    re = Regex::Automata::DFA::Regex.builder.build_from_dfas(forward, reverse)
  end
  input = Regex::Automata::Input.new(test.haystack)
    .range(test.bounds[0]...test.bounds[1])
    .anchored(test.anchored ? Regex::Automata::Anchored::Yes : Regex::Automata::Anchored::No)
  expected = test.matches.map { |mat| {mat.id, mat.span[0], mat.span[1]} }
  actual_match = re.is_match(input.clone)
  raise "#{mode}: #{test.full_name} is_match #{actual_match} != #{!expected.empty?}" unless actual_match == !expected.empty?

  if test.search_kind == "overlapping"
    actual = [] of Tuple(Int32, Int32, Int32)
    fwd_state = Regex::Automata::OverlappingState.start
    loop do
      result = re.forward.try_search_overlapping_fwd(input, fwd_state)
      raise "#{mode}: #{test.full_name} forward overlap #{result}" if result.is_a?(Regex::Automata::MatchError)
      break unless finish = fwd_state.get_match

      rev_input = input.clone.range(input.start...finish.offset)
        .anchored_pattern(finish.pattern)
        .earliest(false)
      rev_state = Regex::Automata::OverlappingState.start
      loop do
        result = re.reverse.try_search_overlapping_rev(rev_input, rev_state)
        raise "#{mode}: #{test.full_name} reverse overlap #{result}" if result.is_a?(Regex::Automata::MatchError)
        break unless start = rev_state.get_match
        actual << {finish.pattern.to_i, start.offset, finish.offset}
      end
    end
    raise "#{mode}: #{test.full_name} overlap find #{actual} != #{expected}" unless actual == expected
    which = Regex::Automata::PatternSet.new(test.patterns.size)
    result = re.forward.try_which_overlapping_matches(input, which)
    raise "#{mode}: #{test.full_name} which overlap #{result}" if result.is_a?(Regex::Automata::MatchError)
    expected_which = expected.map(&.[0]).uniq.sort
    actual_which = which.iter.map(&.to_i).to_a
    raise "#{mode}: #{test.full_name} which #{actual_which} != #{expected_which}" unless actual_which == expected_which
  else
    limit = Math.min(test.match_limit || Int32::MAX, expected.size + 2)
    actual = re.find_iter(input.clone.earliest(test.search_kind == "earliest"))
      .first(limit)
      .map { |mat| {mat.pattern.to_i, mat.start, mat.end} }.to_a
    raise "#{mode}: #{test.full_name} find #{actual} != #{expected}" unless actual == expected
  end
end

describe "pinned dense DFA TOML suite" do
  it "minimized_default: regression/reverse-suffix-all-no-early-matches-010" do
    test = VendorRegexSuite.load.cases("regression").find { |entry| entry.name == "reverse-suffix-all-no-early-matches-010" }.not_nil!
    dense_vendor_check(test, "minimized_default")
  end

  it "minimized_no_byte_class: unicode/class9" do
    test = VendorRegexSuite.load.cases("unicode").find { |entry| entry.name == "class9" }.not_nil!
    dense_vendor_check(test, "minimized_no_byte_class")
  end

  %w(default prefilter specialized_start_states no_byte_class nfa_shrink minimized_default minimized_no_byte_class serialization).each do |mode|
    VendorRegexSuite.load.groups.each do |group|
      next if group == "expensive" # Rust TestRunner::blacklist("expensive").
      it "#{mode}: #{group} is_match/find/which" do
        VendorRegexSuite.load.cases(group).each do |test|
          dense_vendor_check(test, mode)
        end
      end
    end
  end
end
