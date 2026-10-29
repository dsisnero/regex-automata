require "./spec_helper"

# Direct port of pinned range_trie.rs::tests::{no_splits,splits}.
# O, N and B denote Rust SplitRange::{Old,New,Both}.
module Regex::Automata::NFA
  class RangeTrie
    def vendor_state_object_ids : Array(UInt64)
      @states.map(&.object_id)
    end
  end

  def self.vendor_split(old_start : Int32, old_end : Int32, new_start : Int32, new_end : Int32) : String?
    old_range = Regex::Automata::Utf8Range.new(old_start.to_u8, old_end.to_u8)
    new_range = Regex::Automata::Utf8Range.new(new_start.to_u8, new_end.to_u8)
    split = RangeTrieSplit.build(old_range, new_range)
    split.try do |value|
      value.map do |part|
        kind = case part.kind
               when RangeTrieSplitKind::Old  then "O"
               when RangeTrieSplitKind::New  then "N"
               when RangeTrieSplitKind::Both then "B"
               end
        "#{kind}#{part.range.start}-#{part.range.end}"
      end.join(",")
    end
  end

  def self.vendor_range_trie_rows : Array(String)
    trie = RangeTrie.new
    trie.insert([Regex::Automata::Utf8Range.new(2_u8, 4_u8)])
    trie.insert([Regex::Automata::Utf8Range.new(3_u8, 5_u8)])
    rows = [] of String
    trie.each do |sequence|
      rows << sequence.map { |range| "#{range.start}-#{range.end}" }.join(",")
    end
    rows
  end

  def self.vendor_range_trie_reuses_states? : Bool
    trie = RangeTrie.new
    trie.insert([Regex::Automata::Utf8Range.new(1_u8, 2_u8), Regex::Automata::Utf8Range.new(3_u8, 4_u8)])
    before = trie.vendor_state_object_ids
    trie.clear
    trie.vendor_state_object_ids.all? { |id| before.includes?(id) }
  end

  def self.vendor_empty_range_trie_debug : String
    RangeTrie.new.inspect
  end

  def self.vendor_nonempty_range_trie_debug : String
    trie = RangeTrie.new
    trie.insert([Regex::Automata::Utf8Range.new(0x41_u8, 0x43_u8)])
    trie.inspect
  end
end

describe "pinned Thompson RangeTrie split partitions" do
  it "returns no split for disjoint ranges in either order" do
    Regex::Automata::NFA.vendor_split(0, 1, 2, 3).should be_nil
    Regex::Automata::NFA.vendor_split(2, 3, 0, 1).should be_nil
  end

  it "matches every pinned overlap and containment partition" do
    {
      {0, 0, 0, 0} => "B0-0", {9, 9, 9, 9} => "B9-9",
      {0, 5, 0, 6} => "B0-5,N6-6", {0, 5, 0, 8} => "B0-5,N6-8",
      {5, 5, 5, 8} => "B5-5,N6-8",
      {1, 5, 0, 5} => "N0-0,B1-5", {3, 5, 0, 5} => "N0-2,B3-5",
      {5, 5, 0, 5} => "N0-4,B5-5",
      {0, 6, 0, 5} => "B0-5,O6-6", {0, 8, 0, 5} => "B0-5,O6-8",
      {5, 8, 5, 5} => "B5-5,O6-8",
      {0, 5, 1, 5} => "O0-0,B1-5", {0, 5, 3, 5} => "O0-2,B3-5",
      {0, 5, 5, 5} => "O0-4,B5-5",
      {3, 6, 2, 7} => "N2-2,B3-6,N7-7", {3, 6, 1, 8} => "N1-2,B3-6,N7-8",
      {2, 7, 3, 6} => "O2-2,B3-6,O7-7", {1, 8, 3, 6} => "O1-2,B3-6,O7-8",
      {3, 6, 6, 7} => "O3-5,B6-6,N7-7", {3, 6, 6, 8} => "O3-5,B6-6,N7-8",
      {5, 6, 6, 7} => "O5-5,B6-6,N7-7",
      {6, 7, 3, 6} => "N3-5,B6-6,O7-7", {6, 8, 3, 6} => "N3-5,B6-6,O7-8",
      {6, 7, 5, 6} => "N5-5,B6-6,O7-7",
      {3, 7, 5, 9} => "O3-4,B5-7,N8-9", {3, 5, 4, 6} => "O3-3,B4-5,N6-6",
      {5, 9, 3, 7} => "N3-4,B5-7,O8-9", {4, 6, 3, 5} => "N3-3,B4-5,O6-6",
    }.each do |(old_start, old_end, new_start, new_end), expected|
      Regex::Automata::NFA.vendor_split(old_start, old_end, new_start, new_end).should eq(expected)
    end
  end

  it "iterates overlapping inserted ranges as sorted disjoint partitions" do
    Regex::Automata::NFA.vendor_range_trie_rows.should eq(["2-2", "3-4", "5-5"])
  end

  it "reuses cleared trie states as Rust's free list does" do
    Regex::Automata::NFA.vendor_range_trie_reuses_states?.should be_true
  end

  it "renders final and root states with Rust Debug labels" do
    Regex::Automata::NFA.vendor_empty_range_trie_debug.should eq("\n*000000: \n 000001: \n")
    Regex::Automata::NFA.vendor_nonempty_range_trie_debug.should eq("\n*000000: \n 000001: 41-43 => 00\n")
  end
end
