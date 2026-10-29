require "./spec_helper"

# Pinned map.rs has no native tests. These characterize its documented
# direct-mapped eviction, exact-key verification, and versioned clear paths.
module Regex::Automata::NFA
  def self.verify_bounded_map_vendor_contract : Nil
    map = Utf8BoundedMap.new(1)
    map.clear
    first = [Transition.new(0x80_u8, 0xBF_u8, StateID.new(1))]
    second = [Transition.new(0xC0_u8, 0xDF_u8, StateID.new(2))]
    map.get(first, map.hash(first)).should be_nil
    map.set(first, map.hash(first), StateID.new(7))
    map.get(first, map.hash(first)).should eq(StateID.new(7))
    map.get(second, map.hash(second)).should be_nil
    map.set(second, map.hash(second), StateID.new(8))
    map.get(first, map.hash(first)).should be_nil
    map.get(second, map.hash(second)).should eq(StateID.new(8))
    map.clear
    map.get(second, map.hash(second)).should be_nil
  end

  def self.verify_suffix_map_vendor_contract : Nil
    map = Utf8SuffixMap.new(1)
    map.clear
    first = Utf8SuffixKey.new(StateID.new(1), 0x80_u8, 0xBF_u8)
    second = Utf8SuffixKey.new(StateID.new(2), 0x80_u8, 0xBF_u8)
    map.get(first, map.hash(first)).should be_nil
    map.set(first, map.hash(first), StateID.new(7))
    map.get(first, map.hash(first)).should eq(StateID.new(7))
    map.get(second, map.hash(second)).should be_nil
    map.set(second, map.hash(second), StateID.new(8))
    map.get(first, map.hash(first)).should be_nil
    map.get(second, map.hash(second)).should eq(StateID.new(8))
    map.clear
    map.get(second, map.hash(second)).should be_nil
  end
end

describe "pinned Thompson UTF-8 cache maps" do
  it "uses bounded-map collision eviction and versioned clear" do
    Regex::Automata::NFA.verify_bounded_map_vendor_contract
  end

  it "uses suffix-map collision eviction and versioned clear" do
    Regex::Automata::NFA.verify_suffix_map_vendor_contract
  end
end
