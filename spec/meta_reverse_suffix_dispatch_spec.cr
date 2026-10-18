require "./spec_helper"

# Mirrors vendor/regex/regex-automata/src/meta/strategy.rs ReverseSuffix and
# vendor/regex/testdata/regression.toml reverse-suffix cases.
class Regex::Automata::Meta::Regex
  def reverse_suffix_selected_for_spec? : Bool
    !@reverse_suffix_prefilter.nil? && (!@reverse_suffix_dfa.nil? || !@reverse_suffix_hybrid.nil?)
  end

  def force_nofail_core_for_suffix_spec : Nil
    @core_dfa = nil
    @core_hybrid = nil
    @core_onepass = nil
    @core_backtrack = nil
  end

  def suffix_start_for_spec(cache : ::Regex::Automata::Meta::Cache, input : ::Regex::Automata::Input)
    reverse_suffix_start(cache, input)
  end

  def suffix_candidate_for_spec(input : ::Regex::Automata::Input)
    @reverse_suffix_prefilter.not_nil!.find(input.haystack, ::Regex::Automata::Span.new(input.start, input.end))
  end

  def suffix_reuses_core_reverse_for_spec? : Bool
    return @reverse_suffix_dfa.same?(@core_dfa.not_nil!.reverse) if @reverse_suffix_dfa
    @reverse_suffix_hybrid.same?(@core_hybrid.not_nil!.reverse)
  end
end

describe "pinned Rust ReverseSuffix dispatch" do
  it "reuses Core's dense or hybrid reverse engine and hybrid cache" do
    dense = Regex::Automata::Meta::Regex.new("\\d+XYZ")
    dense.reverse_suffix_selected_for_spec?.should be_true
    dense.suffix_reuses_core_reverse_for_spec?.should be_true

    hybrid = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false))
      .build("\\d+XYZ")
    hybrid.reverse_suffix_selected_for_spec?.should be_true
    hybrid.suffix_reuses_core_reverse_for_spec?.should be_true
    cache = hybrid.create_cache
    cache.reverse_suffix_hybrid_cache.same?(cache.core_hybrid_cache.not_nil!.reverse).should be_true
  end

  it "ports the pinned strategy.rs ReverseSuffix admission matrix" do
    accepted = [
      "\\d+XYZ", "[a-q][^u-z]{13}x", "\\w+\\s+Holmes",
      "\\w+\\d*\\s+Holmes", "(?:\\w+|[.-]+)+\\s+Holmes",
      "\\b\\w+\\s+Holmes", "\\w+\\sHolmes", "[a-z]+[0-9]+Holmes",
      "(\\w+)(\\s+)Holmes", "(?-u:[A-Za-z]+[0-9]+Holmes)",
      "[A-Z][0-9]XYZ",
    ]
    accepted.each do |pattern|
      Regex::Automata::Meta::Regex.new(pattern).reverse_suffix_selected_for_spec?.should be_true
    end

    rejected = [
      "\\b\\w+nn\\b", "\\w+\\w+Holmes", "\\w+\\s*Holmes",
      "[a-z]+[0-9a]+xyz", "[a-z]+[0-9]+a1", "(?:.abc)?[a]+[b]+c",
      "(a|aa)b", "^\\d+XYZ", "(?:[A-Za-z]ab)?b", "abc\\w+XYZ",
      "[a-z]+", ".abb|b", ".bb|b", "(?:[a-wyz]{3}|[a-wyz]).b",
      "(?:[ac-z]{2}b[ac-z])?[ac-z]b", "(?:[a-z]cb|c)[a-z]*b",
    ]
    rejected.each do |pattern|
      Regex::Automata::Meta::Regex.new(pattern).reverse_suffix_selected_for_spec?.should be_false
    end

    [["\\d+XYZ", "\\w+XYZ"], ["\\d+XYZ", "\\w+ABC"],
     ["\\d+b", ".bb|b"], ["\\d+b", "ab"]].each do |patterns|
      Regex::Automata::Meta::Regex.builder.build_many(patterns).reverse_suffix_selected_for_spec?.should be_false
    end

    [Regex::Automata::Meta::Regex.config.auto_prefilter(false),
     Regex::Automata::Meta::Regex.config.match_kind(Regex::Automata::MatchKind::All),
     Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false)].each do |config|
      Regex::Automata::Meta::Regex.builder.configure(config).build("\\d+XYZ")
        .reverse_suffix_selected_for_spec?.should be_false
    end
  end

  it "ports regression.toml reverse-suffix-100 and reverse-suffix-200" do
    Regex::Automata::Meta::Regex.new("[0-4][0-4][0-4]000")
      .find("153.230000").should eq(Regex::Automata::Match.must(0, 4...10))
    re = Regex::Automata::Meta::Regex.new("[0-9][0-9][0-9]000")
    re.reverse_suffix_selected_for_spec?.should be_true
    input = Regex::Automata::Input.new("153.230000\n")
    re.suffix_candidate_for_spec(input).should eq(Regex::Automata::Span.new(6, 9))
    re.suffix_start_for_spec(re.create_cache, input)
      .should be_a(Regex::Automata::Meta::RetryQuadraticError)
    re.find("153.230000\n").should eq(Regex::Automata::Match.must(0, 4...10))
  end

  it "ports regression.toml reverse-suffix-300 word-boundary rejection" do
    re = Regex::Automata::Meta::Regex.builder
      .syntax(Regex::Automata::Syntax::Config.new.unicode(false).utf8(false))
      .build("\\w+foobar\\b")
    re.find("xyzfoobarZ").should be_nil
  end

  it "ends a clean suffix miss without Core work" do
    re = Regex::Automata::Meta::Regex.new("\\d+XYZ")
    re.reverse_suffix_selected_for_spec?.should be_true
    cache = re.create_cache
    re.force_nofail_core_for_suffix_spec
    re.search_with(cache, Regex::Automata::Input.new("123ABC")).should be_nil
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "does not retry Core for half-match, capture, or slot misses" do
    re = Regex::Automata::Meta::Regex.new("(\\d+)XYZ")
    re.reverse_suffix_selected_for_spec?.should be_true
    cache = re.create_cache
    re.force_nofail_core_for_suffix_spec
    input = Regex::Automata::Input.new("123ABC")
    re.search_half_with(cache, input).should be_nil
    caps = re.create_captures
    re.search_captures_with(cache, input, caps)
    caps.get_match.should be_nil
    slots = [0, 3, 0, 3] of Int32?
    re.search_slots_with(cache, input, slots).should be_nil
    slots.should eq([nil, nil, nil, nil])
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "routes an explicitly anchored search to Core" do
    re = Regex::Automata::Meta::Regex.new("\\d+XYZ")
    re.reverse_suffix_selected_for_spec?.should be_true
    cache = re.create_cache
    re.force_nofail_core_for_suffix_spec
    re.search_with(cache, Regex::Automata::Input.new("123XYZ").anchored(Regex::Automata::Anchored::Yes))
      .should eq(Regex::Automata::Match.must(0, 0...6))
    cache.pike_scratch_allocated_for_spec?.should be_true
  end

  it "confirms a suffix start with Core's forward DFA, without PikeVM scratch" do
    re = Regex::Automata::Meta::Regex.new("\\d+XYZ")
    re.reverse_suffix_selected_for_spec?.should be_true
    cache = re.create_cache
    input = Regex::Automata::Input.new("xx123XYZ!")
    re.search_with(cache, input).should eq(Regex::Automata::Match.must(0, 2...8))
    cache.pike_scratch_allocated_for_spec?.should be_false
    re.search_half_with(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 8))
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "uses Core's no-fail capture engine after suffix start discovery" do
    re = Regex::Automata::Meta::Regex.new("(?P<digits>\\d+)XYZ")
    re.reverse_suffix_selected_for_spec?.should be_true
    cache = re.create_cache
    caps = re.create_captures
    re.search_captures_with(cache, Regex::Automata::Input.new("xx123XYZ!"), caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 2...8))
    caps.get_group_by_name("digits").should eq(Regex::Automata::Span.new(2, 5))
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "reports overlapping patterns through Core" do
    re = Regex::Automata::Meta::Regex.new("\\d+XYZ")
    re.reverse_suffix_selected_for_spec?.should be_true
    matches = Regex::Automata::PatternSet.new(1)
    re.which_overlapping_matches_with(re.create_cache, Regex::Automata::Input.new("123XYZ"), matches)
    matches.iter.to_a.should eq([Regex::Automata::PatternID.new(0)])
  end

  it "falls back to Core no-fail when reverse DFA quits on Unicode context" do
    re = Regex::Automata::Meta::Regex.new("\\b\\w+\\s+Holmes")
    re.reverse_suffix_selected_for_spec?.should be_true
    input = Regex::Automata::Input.new("élan Holmes")
    re.suffix_start_for_spec(re.create_cache, input).should be_a(Regex::Automata::Meta::RetryFailError)
    re.find(input).should eq(Regex::Automata::Match.must(0, 0...12))
  end
end
