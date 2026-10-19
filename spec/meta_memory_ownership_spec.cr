require "./spec_helper"

# Source: pinned regex-automata src/meta/{strategy,regex}.rs memory_usage,
# Core/ReverseAnchored/ReverseSuffix/ReverseInner cache constructors.
class Regex::Automata::Meta::Regex
  def memory_reverse_anchored_selected_for_spec? : Bool
    !@reverse_anchored_dfa.nil? || !@reverse_anchored_hybrid.nil?
  end

  def memory_reverse_suffix_selected_for_spec? : Bool
    !@reverse_suffix_prefilter.nil? && (!@reverse_suffix_dfa.nil? || !@reverse_suffix_hybrid.nil?)
  end

  def memory_reverse_inner_selected_for_spec? : Bool
    !@reverse_inner_prefilter.nil? && (!@reverse_inner_dfa.nil? || !@reverse_inner_hybrid.nil?)
  end

  def memory_reverse_anchored_dense_for_spec : ::Regex::Automata::DFA::DFA?
    @reverse_anchored_dfa
  end

  def core_memory_for_spec : UInt64
    @info_memory_usage.to_u64 + @nfa.not_nil!.memory_usage.to_u64 +
      (@core_prefilter.try(&.memory_usage.to_u64) || 0_u64) +
      (@core_reverse_nfa.try(&.memory_usage.to_u64) || 0_u64) +
      (@core_onepass.try(&.memory_usage.to_u64) || 0_u64) +
      (@core_dfa.try { |dfa| dfa.forward.memory_usage.to_u64 + dfa.reverse.memory_usage.to_u64 } || 0_u64)
  end

  def reverse_suffix_prefilter_memory_for_spec : UInt64
    @reverse_suffix_prefilter.not_nil!.memory_usage.to_u64
  end

  def reverse_inner_extra_memory_for_spec : UInt64
    @reverse_inner_prefilter.not_nil!.memory_usage.to_u64 +
      (@reverse_inner_dfa.try(&.memory_usage.to_u64) || 0_u64)
  end

  def reverse_inner_nfa_memory_for_spec : UInt64
    @reverse_inner_nfa.not_nil!.memory_usage.to_u64
  end
end

describe "pinned Rust Meta strategy memory ownership" do
  it "reports only Core memory for ReverseAnchored and reuses Core's reverse DFA" do
    re = Regex::Automata::Meta::Regex.new("foo$")
    re.memory_reverse_anchored_selected_for_spec?.should be_true
    re.memory_usage.should eq(re.core_memory_for_spec)
    re.memory_reverse_anchored_dense_for_spec.not_nil!.same?(re.core_dfa.not_nil!.reverse).should be_true
  end

  it "reuses Core's reverse hybrid cache without counting it twice" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false))
      .build("\\w+Holmes$")
    re.memory_reverse_anchored_selected_for_spec?.should be_true
    cache = re.create_cache
    cache.reverse_anchored_hybrid_cache.not_nil!.same?(cache.core_hybrid_cache.not_nil!.reverse).should be_true
    cache.memory_usage.should eq(cache.core_hybrid_cache.not_nil!.memory_usage +
                                 (cache.core_onepass_cache.try(&.memory_usage.to_u64) || 0_u64) +
                                 (cache.core_backtrack_cache.try(&.memory_usage.to_u64) || 0_u64))
    re.memory_usage.should eq(re.core_memory_for_spec)
  end

  it "adds only the selected reverse-suffix prefilter to Core memory" do
    re = Regex::Automata::Meta::Regex.new("[a-z]shing")
    re.memory_reverse_suffix_selected_for_spec?.should be_true
    re.memory_usage.should eq(re.core_memory_for_spec + re.reverse_suffix_prefilter_memory_for_spec)
  end

  it "accounts for ReverseInner's dedicated reverse-prefix NFA and reverse engine" do
    re = Regex::Automata::Meta::Regex.new("\\w+@\\w+")
    re.memory_reverse_inner_selected_for_spec?.should be_true
    re.reverse_inner_nfa_memory_for_spec.should be > 0_u64
    # For a dense reverse engine, the dedicated NFA is not otherwise owned
    # by the DFA, and Rust counts both independently.
    re.memory_usage.should eq(re.core_memory_for_spec +
                              re.reverse_inner_extra_memory_for_spec +
                              re.reverse_inner_nfa_memory_for_spec)
  end

  it "counts both the Core and reverse-prefix hybrid caches, then preserves them on reset" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false))
      .build("\\w+@\\w+")
    re.memory_reverse_inner_selected_for_spec?.should be_true
    re.memory_usage.should eq(re.core_memory_for_spec +
                              re.reverse_inner_extra_memory_for_spec +
                              re.reverse_inner_nfa_memory_for_spec)
    cache = re.create_cache
    cache.reverse_inner_hybrid_cache.should_not be_nil
    cache.reverse_inner_hybrid_cache.not_nil!.same?(cache.core_hybrid_cache.not_nil!.reverse).should be_false
    before = cache.memory_usage
    re.reset(cache)
    cache.reverse_inner_hybrid_cache.should_not be_nil
    cache.memory_usage.should be >= before
  end

  it "follows Rust's lazy backtracker/PikeVM cache creation and reset ownership" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false))
      .build("[a-z]+")
    cache = re.create_cache
    cache.core_backtrack_cache.should be_nil
    cache.pike_scratch_allocated_for_spec?.should be_false
    re.reset(cache)
    cache.core_backtrack_cache.should_not be_nil
    cache.pike_scratch_allocated_for_spec?.should be_true
  end

  it "retains optional wrapper-cache allocations when reset to a regex without those engines" do
    hybrid = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false))
      .build("\\w+@\\w+")
    cache = hybrid.create_cache
    old_core = cache.core_hybrid_cache.not_nil!
    old_reverse = cache.reverse_inner_hybrid_cache.not_nil!
    before = cache.memory_usage

    plain = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false).backtrack(false))
      .build("[a-z]+")
    cache.reset(plain)
    cache.core_hybrid_cache.not_nil!.same?(old_core).should be_true
    cache.reverse_inner_hybrid_cache.not_nil!.same?(old_reverse).should be_true
    cache.memory_usage.should be >= before

    literal = Regex::Automata::Meta::Regex.new("Sherlock")
    cache.reset(literal)
    cache.core_hybrid_cache.not_nil!.same?(old_core).should be_true
    cache.reverse_inner_hybrid_cache.not_nil!.same?(old_reverse).should be_true
  end
end
