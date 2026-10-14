require "./spec_helper"
require "json"

private record HybridOverlapCase,
  name : String,
  patterns : Array(String),
  haystack : String | Bytes,
  line_terminator : UInt8,
  bounds : Tuple(Int32, Int32),
  anchored : Bool,
  utf8 : Bool,
  unicode : Bool,
  case_insensitive : Bool,
  kind : Regex::Automata::MatchKind,
  overlapping : Bool,
  matches : Array(Tuple(Int32, Int32, Int32))

private def overlap_scalar(block : String, key : String) : String?
  prefix = "#{key} ="
  block.each_line do |line|
    next unless line.starts_with?(prefix)
    value = line[prefix.size..].strip
    if value.starts_with?("'") || value.starts_with?("\"")
      quote = value[0]
      return value[0..value.rindex(quote).not_nil!]
    end
    return value if value.starts_with?('[')
    return value.split('#', 2)[0].strip
  end
  nil
end

private def overlap_string(value : String) : String
  return value[1...-1] unless value.starts_with?('"')

  normalized = value.gsub(/\\U([0-9A-Fa-f]{8})/) do |matched|
    matched[2..].to_i(16).chr.to_s
  end
  JSON.parse(normalized).as_s
end

private def overlap_unescape_bytes(value : String) : Bytes
  raw = value.to_slice
  bytes = [] of UInt8
  at = 0
  while at < raw.size
    if raw[at] == '\\'.ord && at + 1 < raw.size
      if raw[at + 1] == 'x'.ord && at + 3 < raw.size
        bytes << String.new(raw[at + 2, 2]).to_u8(16)
        at += 4
        next
      elsif raw[at + 1] == '\\'.ord
        bytes << '\\'.ord.to_u8
        at += 2
        next
      elsif raw[at + 1] == 'n'.ord
        bytes << '\n'.ord.to_u8
        at += 2
        next
      elsif raw[at + 1] == 'r'.ord
        bytes << '\r'.ord.to_u8
        at += 2
        next
      elsif raw[at + 1] == 't'.ord
        bytes << '\t'.ord.to_u8
        at += 2
        next
      end
    end
    bytes << raw[at]
    at += 1
  end
  Bytes.new(bytes.size) { |i| bytes[i] }
end

private def overlap_cases(file : String) : Array(HybridOverlapCase)
  path = File.join(__DIR__, "..", "vendor", "regex", "testdata", "#{file}.toml")
  File.read(path).split("[[test]]").skip(1).map do |block|
    name = overlap_string(overlap_scalar(block, "name") || raise "name missing")
    pattern_value = overlap_scalar(block, "regex") || raise "regex missing"
    patterns = if pattern_value.starts_with?("[")
                 single_quoted = pattern_value.scan(/'([^']*)'/).map { |match| match[1] }
                 single_quoted.empty? ? JSON.parse(pattern_value).as_a.map(&.as_s) : single_quoted
               else
                 [overlap_string(pattern_value)]
               end
    haystack_string = overlap_string(overlap_scalar(block, "haystack") || raise "haystack missing")
    haystack = if overlap_scalar(block, "unescape") == "true"
                 overlap_unescape_bytes(haystack_string)
               else
                 haystack_string
               end
    line_terminator = if raw = overlap_scalar(block, "line-terminator")
                        bytes = overlap_unescape_bytes(overlap_string(raw))
                        raise "line terminator must be one byte" unless bytes.size == 1
                        bytes[0]
                      else
                        '\n'.ord.to_u8
                      end
    bounds = if raw = overlap_scalar(block, "bounds")
               pair = JSON.parse(raw).as_a
               {pair[0].as_i, pair[1].as_i}
             else
               {0, haystack.bytesize.to_i32}
             end
    offset = block.index("matches =") || raise "matches missing"
    start = block.index('[', offset) || raise "matches array missing"
    depth = 0
    finish = start
    while finish < block.size
      depth += 1 if block[finish] == '['
      depth -= 1 if block[finish] == ']'
      break if depth == 0
      finish += 1
    end
    raw = block[start..finish]
    raw = raw.gsub(/\b(id|span|spans)\s*=/) do |matched|
      %("#{matched.split('=')[0].strip}":)
    end
    values = JSON.parse(raw.gsub(/,\s*\]/, "]")).as_a
    matches = values.map do |value|
      if table = value.as_h?
        span = (table["span"]? || table["spans"].as_a[0]).as_a
        {table["id"].as_i, span[0].as_i, span[1].as_i}
      else
        entry = value.as_a
        span = entry[0].as_a? || entry
        {0, span[0].as_i, span[1].as_i}
      end
    end
    HybridOverlapCase.new(name, patterns, haystack, line_terminator, bounds,
      overlap_scalar(block, "anchored") == "true",
      overlap_scalar(block, "utf8") != "false",
      overlap_scalar(block, "unicode") != "false",
      overlap_scalar(block, "case-insensitive") == "true",
      overlap_scalar(block, "match-kind") == %q("all") ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst,
      overlap_scalar(block, "search-kind") == %q("overlapping"),
      matches)
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
    return re.find_iter(cache, input).map { |mat| {mat.pattern.to_i, mat.start, mat.end} }.to_a
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
