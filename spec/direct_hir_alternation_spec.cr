require "./spec_helper"
require "./support/thompson_graph_snapshot"

describe "direct literal alternations against Rust smart-constructor graphs" do
  File.each_line("#{__DIR__}/fixtures/direct_hir_alternation.tsv") do |line|
    next if line.empty? || line.starts_with?('#')
    name, configuration, bytes_hex, expected = line.split('\t')
    {"smart", "raw"}.each do |construction|
      it "matches #{name} #{construction} #{configuration}" do
        nfa = ThompsonGraphSnapshot.build("#{name}_#{construction}", configuration, bytes_hex)
        ThompsonGraphSnapshot.snapshot(nfa).should eq(expected)
      end
    end
  end
end
