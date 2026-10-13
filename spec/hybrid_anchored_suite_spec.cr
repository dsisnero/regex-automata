require "./spec_helper"
require "json"

private record HybridSuiteCase,
  name : String,
  pattern : String,
  haystack : String,
  matches : Array(Tuple(Int32, Int32)),
  bounds : Tuple(Int32, Int32),
  anchored : Bool,
  unicode : Bool,
  earliest : Bool,
  match_kind : Regex::Automata::MatchKind

private def anchored_suite_scalar(block : String, key : String) : String?
  prefix = "#{key} ="
  block.each_line do |line|
    return line[prefix.size..].strip if line.starts_with?(prefix)
  end
  nil
end

private def anchored_suite_string(value : String) : String
  return JSON.parse(value).as_s if value.starts_with?('"')
  return value[1...-1] if value.starts_with?("'") && value.ends_with?("'")

  raise "unsupported TOML string #{value.inspect}"
end

private def anchored_suite_matches(block : String) : Array(Tuple(Int32, Int32))
  offset = block.index("matches =") || raise "missing matches"
  start = block.index('[', offset) || raise "missing matches array"
  depth = 0
  index = start
  finish = nil.as(Int32?)
  while index < block.size
    case block[index]
    when '[' then depth += 1
    when ']'
      depth -= 1
      if depth == 0
        finish = index
        break
      end
    end
    index += 1
  end
  raise "unterminated matches array" unless finish

  values = JSON.parse(block[start..finish].gsub(/,\s*\]/, "]")).as_a
  values.map do |value|
    entry = value.as_a
    span = entry[0].as_a? || entry
    {span[0].as_i, span[1].as_i}
  end
end

private def hybrid_suite_cases(file : String) : Array(HybridSuiteCase)
  path = File.join(__DIR__, "..", "vendor", "regex", "testdata", "#{file}.toml")
  File.read(path).split("[[test]]").skip(1).map do |block|
    name = anchored_suite_string(anchored_suite_scalar(block, "name") || raise "missing name")
    pattern = anchored_suite_string(anchored_suite_scalar(block, "regex") || raise "missing regex")
    haystack = anchored_suite_string(anchored_suite_scalar(block, "haystack") || raise "missing haystack")
    bounds = if raw = anchored_suite_scalar(block, "bounds")
               pair = raw.match(/\[\s*(\d+)\s*,\s*(\d+)\s*\]/) ||
                      raw.match(/\{\s*start\s*=\s*(\d+)\s*,\s*end\s*=\s*(\d+)\s*\}/) || raise "invalid bounds"
               {pair[1].to_i32, pair[2].to_i32}
             else
               {0, haystack.bytesize.to_i32}
             end
    HybridSuiteCase.new(
      name,
      pattern,
      haystack,
      anchored_suite_matches(block),
      bounds,
      anchored_suite_scalar(block, "anchored") == "true",
      anchored_suite_scalar(block, "unicode") != "false",
      anchored_suite_scalar(block, "search-kind") == %q("earliest"),
      anchored_suite_scalar(block, "match-kind") == %q("all") ? Regex::Automata::MatchKind::All : Regex::Automata::MatchKind::LeftmostFirst
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
  if mode == "prefilter"
    hir = Regex::Automata::Syntax.parse_with(fixture.pattern, Regex::Automata::Syntax::Config.new.unicode(fixture.unicode))
    config.prefilter(Regex::Automata::Prefilter.from_hir_prefix(fixture.match_kind, hir))
  end
  builder = Regex::Automata::Hybrid::Regex.builder
    .dfa(config)
    .syntax(Regex::Automata::Syntax::Config.new.unicode(fixture.unicode))
  builder.thompson(Regex::Automata::NFA::NFA.config.shrink(true)) if mode == "nfa_shrink"
  re = builder.build(fixture.pattern)
  cache = re.create_cache
  input = Regex::Automata::Input.new(fixture.haystack)
    .range(fixture.bounds[0]...fixture.bounds[1])
    .anchored(fixture.anchored ? Regex::Automata::Anchored::Yes : Regex::Automata::Anchored::No)

  re.is_match(cache, input).should eq(!fixture.matches.empty?)
  got = re.find_iter(cache, input.earliest(fixture.earliest)).map do |mat|
    {mat.start, mat.end}
  end.to_a
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
