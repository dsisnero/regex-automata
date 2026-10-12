require "./spec_helper"
require "./support/thompson_graph_snapshot"

describe "pinned Rust Thompson graphs with the installed regex-syntax dependency" do
  it "adopts the reviewed syntax normalization and public API fixes" do
    node = Regex::Syntax.parse("a|b").node
    node.should be_a(Regex::Syntax::Hir::UnicodeClass)
    node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([0x61_u32..0x62_u32])
    Regex::Syntax::Hir::LookSet.full.bits.should eq(UInt32::MAX)
    Regex::Syntax::Hir::LookSet.full.len.should eq(32)
    Regex::Syntax::Hir::ClassBytesRange.new(0_u8, 255_u8).len.should eq(256)
  end
  File.each_line("#{__DIR__}/fixtures/thompson_syntax_adoption.tsv") do |line|
    next if line.empty? || line.starts_with?('#')
    name, configuration, patterns_hex, expected = line.split('\t')
    it "matches #{name} #{configuration} #{patterns_hex}" do
      nfa = ThompsonGraphSnapshot.build(name, configuration, patterns_hex)
      ThompsonGraphSnapshot.snapshot(nfa).should eq(expected)
    end
  end
end
