require "./spec_helper"

# Rust meta::regex::Config stores this setting as Option<usize> and forwards
# it unchanged to both lazy DFA builders.
describe "pinned Rust Meta hybrid cache capacity" do
  it "defaults to two MiB and preserves explicit usize-width values" do
    config = Regex::Automata::Meta::Regex.config
    config.get_hybrid_cache_capacity.should eq(2_097_152_u64)

    wide = 1_u64 << 33
    config.hybrid_cache_capacity(wide).get_hybrid_cache_capacity.should eq(wide)
  end

  it "uses the last explicit value when merging configurations" do
    base = Regex::Automata::Meta::Regex.config.hybrid_cache_capacity(1_u64 << 33)
    other = Regex::Automata::Meta::Regex.config.hybrid_cache_capacity(1_u64 << 34)
    base.overwrite(other).get_hybrid_cache_capacity.should eq(1_u64 << 34)
    base.overwrite(Regex::Automata::Meta::Regex.config).get_hybrid_cache_capacity.should eq(1_u64 << 33)
  end

  it "passes a wide requested capacity to a selected lazy DFA" do
    wide = 1_u64 << 33
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).auto_prefilter(false).hybrid_cache_capacity(wide))
      .build("[a-z]+")
    re.core_hybrid.should_not be_nil
    re.core_hybrid.not_nil!.forward.get_config.get_cache_capacity.should eq(wide)
    re.core_hybrid.not_nil!.reverse.get_config.get_cache_capacity.should eq(wide)
  end
end
