require "./spec_helper"

# Pinned Rust: vendor/regex/regex-automata/src/meta/{strategy,reverse_inner,reverse_suffix}.rs
# and vendor/regex/testdata/{regression,anchored}.toml.
class Regex::Automata::Meta::Regex
  def reverse_inner_selected_for_spec? : Bool
    !@reverse_inner_prefilter.nil? && (!@reverse_inner_dfa.nil? || !@reverse_inner_hybrid.nil?)
  end

  def force_nofail_core_for_inner_spec : Nil
    @core_dfa = nil
    @core_hybrid = nil
    @core_onepass = nil
    @core_backtrack = nil
  end

  def inner_search_for_spec(cache : ::Regex::Automata::Meta::Cache, input : ::Regex::Automata::Input)
    reverse_inner_search(cache, input)
  end

  def inner_reuses_core_forward_for_spec? : Bool
    return @reverse_inner_forward_dfa.same?(@core_dfa.not_nil!.forward) if @reverse_inner_forward_dfa
    @reverse_inner_forward_hybrid.same?(@core_hybrid.not_nil!.forward)
  end
end

class Regex::Automata::Meta::Builder
  def strip_suffix_for_spec(pattern : String, suffix : String) : ::Regex::Syntax::Hir::Hir?
    strip_literal_suffix(::Regex::Syntax.parse(pattern), suffix.to_slice)
  end

  def suffix_fixed_length_for_spec?(pattern : String, suffix : String) : Bool
    prefix = strip_suffix_for_spec(pattern, suffix)
    !prefix.nil? && hir_has_fixed_length?(prefix)
  end

  def suffix_can_occur_in_prefix_for_spec?(pattern : String, suffix : String) : Bool
    prefix = strip_suffix_for_spec(pattern, suffix)
    !prefix.nil? && hir_can_contain_literal?(prefix, suffix.to_slice)
  end
end

describe "pinned Rust ReverseInner strategy" do
  it "reuses Core's forward DFA or lazy DFA and its cache" do
    dense = Regex::Automata::Meta::Regex.new("\\w+@\\w+")
    dense.reverse_inner_selected_for_spec?.should be_true
    dense.inner_reuses_core_forward_for_spec?.should be_true

    hybrid = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false))
      .build("\\w+@\\w+")
    hybrid.reverse_inner_selected_for_spec?.should be_true
    hybrid.inner_reuses_core_forward_for_spec?.should be_true
    cache = hybrid.create_cache
    cache.reverse_inner_forward_hybrid_cache.same?(cache.core_hybrid_cache.not_nil!.forward).should be_true
  end

  it "ports the strategy.rs ReverseInner selector matrix" do
    accepted = [
      "\\w+@\\w+", "(?P<email>[.\\pL]+@(?P<domain>[.\\pL]+))",
      "[A-Z][0-9]@(foo|bar)", "\\w+\\s+Holmes\\s+\\w+",
      "\\w+\\d*\\s+Holmes\\s+\\w+", "\\b\\w+\\s+Holmes\\s+\\w+",
      "\\w+\\s+(?:Holmes|Watson)\\s+\\w+", "\\s[A-Za-z]{0,12}ing\\s",
      "\\s[A-Za-z]*ing\\s", "\\b\\s[A-Za-z]{0,12}ing\\s",
      "(\\s)([A-Za-z]{0,12})ing\\s",
    ]
    accepted.each do |pattern|
      Regex::Automata::Meta::Regex.new(pattern).reverse_inner_selected_for_spec?.should be_true
    end

    rejected = [
      "\\s[\\sA-Za-z]{0,12}ing\\s", "\\s*[A-Za-z]{0,12}ing\\s",
      "^\\w+@\\w+", "abc\\w+@\\w+", "\\w+", "a.*@\\w+",
      "(?:[ac-z]{3}|[ac-z])(?:aba|baa)", "(?:.abc)?[a]+[b]+c.*",
    ]
    rejected.each do |pattern|
      Regex::Automata::Meta::Regex.new(pattern).reverse_inner_selected_for_spec?.should be_false
    end
    Regex::Automata::Meta::Regex.builder.build_many(["\\w+@\\w+", "\\w+#\\w+"])
      .reverse_inner_selected_for_spec?.should be_false
    [Regex::Automata::Meta::Regex.config.auto_prefilter(false),
     Regex::Automata::Meta::Regex.config.match_kind(Regex::Automata::MatchKind::All),
     Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false)].each do |config|
      Regex::Automata::Meta::Regex.builder.configure(config).build("\\w+@\\w+")
        .reverse_inner_selected_for_spec?.should be_false
    end
  end

  it "ends a clean inner-prefilter miss without Core work" do
    re = Regex::Automata::Meta::Regex.new("\\w+@\\w+")
    re.reverse_inner_selected_for_spec?.should be_true
    cache = re.create_cache
    re.force_nofail_core_for_inner_spec
    re.search_with(cache, Regex::Automata::Input.new("plain words")).should be_nil
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "ends half-match, capture, and slot misses without a Core search" do
    re = Regex::Automata::Meta::Regex.new("(?P<lhs>\\w+)@\\w+")
    re.reverse_inner_selected_for_spec?.should be_true
    cache = re.create_cache
    re.force_nofail_core_for_inner_spec
    input = Regex::Automata::Input.new("plain words")
    re.search_half_with(cache, input).should be_nil
    re.is_match_with(cache, input).should be_false
    caps = re.create_captures
    re.search_captures_with(cache, input, caps)
    caps.get_match.should be_nil
    slots = [0, 2, 0, 2] of Int32?
    re.search_slots_with(cache, input, slots).should be_nil
    slots.should eq([nil, nil, nil, nil])
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "routes explicitly anchored searches to Core" do
    re = Regex::Automata::Meta::Regex.new("\\w+@\\w+")
    re.reverse_inner_selected_for_spec?.should be_true
    cache = re.create_cache
    re.force_nofail_core_for_inner_spec
    re.search_with(cache, Regex::Automata::Input.new("abc@example").anchored(Regex::Automata::Anchored::Yes))
      .should eq(Regex::Automata::Match.must(0, 0...11))
    cache.pike_scratch_allocated_for_spec?.should be_true
  end

  it "confirms the forward end and reruns explicit captures without PikeVM" do
    re = Regex::Automata::Meta::Regex.new("(?P<lhs>[a-z]+)XYZ\\d+")
    re.reverse_inner_selected_for_spec?.should be_true
    cache = re.create_cache
    input = Regex::Automata::Input.new("!abcXYZ123?")
    re.search_with(cache, input).should eq(Regex::Automata::Match.must(0, 1...10))
    re.search_half_with(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 10))
    re.is_match_with(cache, input).should be_true
    caps = re.create_captures
    re.search_captures_with(cache, input, caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 1...10))
    caps.get_group_by_name("lhs").should eq(Regex::Automata::Span.new(1, 4))
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "delegates overlapping pattern discovery to Core" do
    re = Regex::Automata::Meta::Regex.new("\\w+@\\w+")
    re.reverse_inner_selected_for_spec?.should be_true
    matches = Regex::Automata::PatternSet.new(1)
    re.which_overlapping_matches_with(re.create_cache, Regex::Automata::Input.new("abc@example"), matches)
    matches.iter.to_a.should eq([Regex::Automata::PatternID.new(0)])
  end

  it "retries through Core no-fail when the reverse DFA quits on Unicode context" do
    re = Regex::Automata::Meta::Regex.new("\\b\\w+@\\w+")
    re.reverse_inner_selected_for_spec?.should be_true
    input = Regex::Automata::Input.new("élan@example")
    re.inner_search_for_spec(re.create_cache, input).should be_a(Regex::Automata::Meta::RetryFailError)
    re.find(input).should eq(Regex::Automata::Match.must(0, 0...13))
  end

  it "continues after a false inner candidate using Rust's stop-at guard" do
    re = Regex::Automata::Meta::Regex.new("\\d+XYZ\\d+")
    re.reverse_inner_selected_for_spec?.should be_true
    cache = re.create_cache
    re.force_nofail_core_for_inner_spec
    re.search_with(cache, Regex::Automata::Input.new("123XYZabc999XYZ456"))
      .should eq(Regex::Automata::Match.must(0, 9...18))
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "ports vendor ReverseInner regressions and anchored misses" do
    [{"(?:([0-9][0-9][0-9]):)?([0-9][0-9]):([0-9][0-9])", "102:12:39", 0...9},
     {"(?:..acbb|b)a(?:c|d)", "xzbacbbac", 1...9},
     {"(?:\\s+.\\w+acbb|b)a(?:c|d)", " xzbacbbac", 0...10},
     {"(?:[ac-z]{3}|[ac-z])(?:aba|baa)", "!aaabaa", 1...7},
     {"\\w+\\s+Holmes\\s+\\w+", "abcHolmes xyz Holmes tail", 10...25},
     {"(?:.abc)?a+b+c.*", "xabcabc", 0...7},
     {"\\s[A-Za-z]{0,12}ing\\s", " xingabcing ", 0...12}].each do |pattern, haystack, span|
      Regex::Automata::Meta::Regex.new(pattern).find(haystack)
        .should eq(Regex::Automata::Match.must(0, span))
    end
    re = Regex::Automata::Meta::Regex.new(".c[a-z]")
    re.find(Regex::Automata::Input.new("abcz").anchored(Regex::Automata::Anchored::Yes)).should be_nil
    re.find(Regex::Automata::Input.new("aabcz").span(1...5).anchored(Regex::Automata::Anchored::Yes)).should be_nil
  end

  it "ports the vendor reverse-inner-plus-shorter-than-expected capture spans" do
    ["(?:(\\d+)[:.])?(\\d{1,2})[:.](\\d{2})",
     "(?:([0-9][0-9][0-9]):)?([0-9][0-9]):([0-9][0-9])"].each do |pattern|
      re = Regex::Automata::Meta::Regex.new(pattern)
      caps = re.create_captures
      re.search_captures_with(re.create_cache, Regex::Automata::Input.new("102:12:39"), caps)
      caps.get_group(0).should eq(Regex::Automata::Span.new(0, 9))
      caps.get_group(1).should eq(Regex::Automata::Span.new(0, 3))
      caps.get_group(2).should eq(Regex::Automata::Span.new(4, 6))
      caps.get_group(3).should eq(Regex::Automata::Span.new(7, 9))
    end
  end

  it "ports the private reverse_suffix.rs HIR rewrite cases" do
    builder = Regex::Automata::Meta::Regex.builder
    [{"foobar", "bar", "foo"}, {"foobar", "foobar", ""},
     {"foobar", "", "foobar"}, {".+foo(bar)", "foobar", ".+"},
     {".+(?:ab){2}cd", "ababcd", ".+"}, {"a(?:)cd", "acd", ""},
     {"az{0}cd", "acd", ""}, {"x(?:ab){3}", "bab", "xaba"},
     {"x(?:ab){2,}", "bab", "x(?:ab)*a"}].each do |pattern, suffix, expected|
      builder.strip_suffix_for_spec(pattern, suffix).try(&.to_s)
        .should eq(Regex::Syntax.parse(expected).to_s)
    end
    [{"az{2}cd", "acd"}, {"az{0,2}cd", "acd"},
     {"foobar", "baz"}, {"foobar", "xfoobar"},
     {"foo[a-z]", "a"}, {"foo(xbar)", "foobar"},
     {"x(?:ab)*cd", "abcd"}].each do |pattern, suffix|
      builder.strip_suffix_for_spec(pattern, suffix).should be_nil
    end
  end

  it "ports the private reverse_suffix.rs fixed-length and internal-suffix proofs" do
    builder = Regex::Automata::Meta::Regex.builder
    builder.suffix_can_occur_in_prefix_for_spec?("\\d+XYZ", "XYZ").should be_false
    builder.suffix_can_occur_in_prefix_for_spec?("[a-q][^u-z]{13}x", "x").should be_false
    builder.suffix_fixed_length_for_spec?("(?:ab|cd)XYZ", "XYZ").should be_true
    builder.suffix_can_occur_in_prefix_for_spec?("[A-Z][0-9]XYZ", "XYZ").should be_true
    builder.suffix_fixed_length_for_spec?("[A-Z][0-9]XYZ", "XYZ").should be_true
    builder.suffix_fixed_length_for_spec?("a{1,3}yy", "yy").should be_false
    builder.suffix_fixed_length_for_spec?("a*yy", "yy").should be_false
  end
end
