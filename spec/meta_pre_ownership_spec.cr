require "./spec_helper"

# Rust's private Pre<P> strategy owns only a prefilter and one implicit group.
class Regex::Automata::Meta::Regex
  def pre_engine_ownership_for_spec : {Bool, Bool, Bool, Bool, Bool}
    {!@literal_prefilter.nil?, !@nfa.nil?, !@pikevm.nil?, !@core_dfa.nil?, !@core_hybrid.nil?}
  end

  def prefilter_memory_for_spec : Int32
    @literal_prefilter.not_nil!.memory_usage
  end

  def core_info_memory_for_spec : Int32
    @info_memory_usage
  end
end

describe "pinned Rust meta Pre ownership" do
  it "short-circuits NFA construction even with a zero NFA size limit" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.nfa_size_limit(0_i64))
      .build("Sherlock")
    re.pre_engine_ownership_for_spec.should eq({true, false, false, false, false})
    re.group_info.pattern_len.should eq(1)
    re.group_info.implicit_slot_len.should eq(2)
    re.group_info.explicit_slot_len.should eq(0)
    re.captures_len.should eq(1)
    re.find("xxSherlock").should eq(Regex::Automata::Match.must(0, 2...10))
  end

  it "counts only the selected prefilter and allocates no engine cache" do
    re = Regex::Automata::Meta::Regex.new("Sherlock")
    re.memory_usage.should eq(re.prefilter_memory_for_spec)
    cache = re.create_cache
    cache.memory_usage.should eq(0)
    cache.pike_scratch_allocated_for_spec?.should be_false
    re.reset(cache)
    cache.memory_usage.should eq(0)
    re.search_with(cache, Regex::Automata::Input.new("Sherlock")).should eq(Regex::Automata::Match.must(0, 0...8))
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "also bypasses the NFA for Rust's large literal-alternation strategy" do
    pattern = Array.new(3_000) { |i| "needle#{i.to_s.rjust(5, '0')}" }.join("|")
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.nfa_size_limit(0_i64))
      .build(pattern)
    re.pre_engine_ownership_for_spec.should eq({true, false, false, false, false})
    re.memory_usage.should eq(re.prefilter_memory_for_spec)
    re.find("xxneedle02999").should eq(Regex::Automata::Match.must(0, 2...13))
  end

  it "allocates PikeVM scratch lazily for Core and preserves it on reset" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false).backtrack(false))
      .build("[a-z]+")
    cache = re.create_cache
    cache.pike_scratch_allocated_for_spec?.should be_false
    re.search_with(cache, Regex::Automata::Input.new("abc")).should eq(Regex::Automata::Match.must(0, 0...3))
    cache.pike_scratch_allocated_for_spec?.should be_true
    re.reset(cache)
    cache.pike_scratch_allocated_for_spec?.should be_true
  end

  it "includes Rust RegexInfo HIR and union-property memory only for Core" do
    hir = Regex::Syntax::ParserBuilder.new.build.parse("[a-z]+")
    expected = hir.properties.memory_usage +
               Regex::Syntax::Hir::Properties.union([hir.properties]).memory_usage
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false).backtrack(false))
      .build_from_hir(hir)
    re.core_info_memory_for_spec.should eq(expected)
    re.memory_usage.should be >= re.pikevm.memory_usage + expected
  end
end
