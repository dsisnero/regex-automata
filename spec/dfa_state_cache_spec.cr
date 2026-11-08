require "./spec_helper"

class Regex::Automata::DFA::Builder
  def encoded_state_keys_for_spec : Array(Bytes)
    @state_map.keys.map(&.to_slice)
  end

  def state_scratch_capacity_for_spec : Int32
    @scratch_state_builder.capacity
  end
end

describe "pinned dense determinizer byte-key cache" do
  it "retains owned distinct keys while recycling the probe builder" do
    nfa = Regex::Automata::HirCompiler.new.build_many(["ab|a", "a+", "(?-u:\\b)abc"])
    builder = Regex::Automata::DFA::Builder.from_nfa(nfa)
    dfa = builder.build
    keys = builder.encoded_state_keys_for_spec
    keys.should_not be_empty
    keys.uniq.size.should eq(keys.size)
    keys.all? { |key| key.size >= 9 }.should be_true
    builder.state_scratch_capacity_for_spec.should be > 0
    original_bytes = dfa.to_bytes_native_endian[0].dup
    repeated = builder.build
    repeated.to_bytes_native_endian[0].should eq(original_bytes)
    dfa.to_bytes_native_endian[0].should eq(original_bytes)
    pike = Regex::Automata::NFA::PikeVM.builder.build_from_nfa(nfa)
    ["", "ab", "aaaa", "zabc", "abc", "!aab!"].each do |haystack|
      expected = pike.find(pike.create_cache, haystack)
        .try { |mat| Regex::Automata::HalfMatch.new(mat.pattern, mat.end) }
      dfa.try_search_fwd(Regex::Automata::Input.new(haystack)).should eq(expected)
    end
  end
end
