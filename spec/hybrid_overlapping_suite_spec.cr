require "./spec_helper"
require "json"

private record HybridOverlapCase,
  name : String,
  patterns : Array(String),
  haystack : String | Bytes,
  utf8 : Bool,
  kind : Regex::Automata::MatchKind,
  matches : Array(Tuple(Int32, Int32, Int32))

private def overlap_scalar(block : String, key : String) : String?
  prefix = "#{key} ="
  block.each_line do |line|
    return line[prefix.size..].split('#', 2)[0].strip if line.starts_with?(prefix)
  end
  nil
end

private def overlap_string(value : String) : String
  value.starts_with?('"') ? JSON.parse(value).as_s : value[1...-1]
end

private def overlap_cases : Array(HybridOverlapCase)
  path = File.join(__DIR__, "..", "vendor", "regex", "testdata", "overlapping.toml")
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
                 hex = haystack_string.scan(/\\x([0-9A-Fa-f]{2})/).map { |match| match[1].to_u8(16) }
                 Bytes.new(hex.size) { |i| hex[i] }
               else
                 haystack_string
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
    raw = raw.gsub(/\{\s*id\s*=\s*(\d+)\s*,\s*span\s*=\s*(\[[^\]]+\])\s*\}/) do |matched|
      match = matched.match(/id\s*=\s*(\d+).*span\s*=\s*(\[[^\]]+\])/) || raise "invalid match table"
      %({"id":#{match[1]},"span":#{match[2]}})
    end
    values = JSON.parse(raw.gsub(/,\s*\]/, "]")).as_a
    matches = values.map do |value|
      if table = value.as_h?
        span = table["span"].as_a
        {table["id"].as_i, span[0].as_i, span[1].as_i}
      else
        entry = value.as_a
        span = entry[0].as_a? || entry
        {0, span[0].as_i, span[1].as_i}
      end
    end
    HybridOverlapCase.new(name, patterns, haystack, overlap_scalar(block, "utf8") != "false",
      overlap_scalar(block, "match-kind") == %q("all") ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst,
      matches)
  end
end

private def hybrid_overlap_matches(fixture : HybridOverlapCase,
                                   mode : String) : Array(Tuple(Int32, Int32, Int32))
  config = Regex::Automata::Hybrid::DFA.config
    .match_kind(fixture.kind)
    .unicode_word_boundary(true)
    .starts_for_each_pattern(true)
  case mode
  when "specialize_start_states" then config.specialize_start_states(true)
  when "no_byte_classes"         then config.byte_classes(false)
  when "no_cache_clearing"       then config.minimum_cache_clear_count(0)
  when "min_cache_capacity"      then config.cache_capacity(0).skip_cache_capacity_check(true)
  end
  syntax = Regex::Automata::Syntax::Config.new.utf8(fixture.utf8)
  if mode == "prefilter"
    hirs = fixture.patterns.map { |pattern| Regex::Automata::Syntax.parse_with(pattern, syntax) }
    config.prefilter(Regex::Automata::Prefilter.from_hirs_prefix(fixture.kind, hirs))
  end
  builder = Regex::Automata::Hybrid::Regex.builder.dfa(config).syntax(syntax)
  thompson = Regex::Automata::NFA::NFA.config.utf8(fixture.utf8)
  thompson = thompson.shrink(true) if mode == "nfa_shrink"
  builder.thompson(thompson)
  re = builder.build_many(fixture.patterns)
  cache = re.create_cache
  input = Regex::Automata::Input.new(fixture.haystack)
  re.is_match(cache, input.earliest(true)).should eq(!fixture.matches.empty?)
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

describe "vendor hybrid overlapping suite" do
  cases = overlap_cases
  cases.size.should eq(23)
  %w(default prefilter nfa_shrink starts_for_each_pattern specialize_start_states no_byte_classes no_cache_clearing min_cache_capacity).each do |mode|
    cases.each do |fixture|
      it "#{mode}: overlapping/#{fixture.name}" do
        hybrid_overlap_matches(fixture, mode).should eq(fixture.matches)
      end
    end
  end
end
