require "./spec_helper"

# Pinned literal_trie.rs::tests::{zap,maker} construct tries directly. Rust's
# test-only compile_to_hir exposes branch order; execute the compiled NFA here
# to assert that same leftmost-first order without adding a production HIR dump.
private def compile_vendor_literal_trie(literals : Array(String), reverse : Bool = false) : Regex::Automata::NFA::NFA
  trie = reverse ? Regex::Automata::NFA::LiteralTrie.reverse : Regex::Automata::NFA::LiteralTrie.forward
  literals.each { |literal| trie.add(literal.to_slice) }
  builder = Regex::Automata::NFA::Builder.new(reverse: reverse)
  builder.start_pattern
  ref = trie.compile(builder)
  cap_start = builder.add_capture_start(Regex::Automata::StateID::ZERO, 0_u32, nil)
  cap_end = builder.add_capture_end(Regex::Automata::StateID::ZERO, 0_u32)
  match = builder.add_match
  builder.patch(cap_start, ref.start)
  builder.patch(ref.end, cap_end)
  builder.patch(cap_end, match)
  builder.finish_pattern(cap_start)
  builder.build(cap_start, cap_start)
end

describe "pinned Thompson LiteralTrie fixtures" do
  it "renders private trie states with Rust Debug labels" do
    trie = Regex::Automata::NFA::LiteralTrie.forward
    trie.add("z".to_slice)
    trie.inspect.should eq("LiteralTrie(\n000000: z => 1\n000001: MATCH\n)\n")
  end

  it "preserves zapper, z, zap branch order" do
    nfa = compile_vendor_literal_trie(["zapper", "z", "zap"])
    vm = Regex::Automata::NFA::PikeVM.new_from_nfa(nfa)
    vm.find(vm.create_cache, "zapper").should eq(Regex::Automata::Match.must(0, 0...6))
    vm.find(vm.create_cache, "zap").should eq(Regex::Automata::Match.must(0, 0...1))
    vm.find(vm.create_cache, "z").should eq(Regex::Automata::Match.must(0, 0...1))
  end

  it "preserves make, maple, maker branch order" do
    nfa = compile_vendor_literal_trie(["make", "maple", "maker"])
    vm = Regex::Automata::NFA::PikeVM.new_from_nfa(nfa)
    vm.find(vm.create_cache, "maker").should eq(Regex::Automata::Match.must(0, 0...4))
    vm.find(vm.create_cache, "maple").should eq(Regex::Automata::Match.must(0, 0...5))
    vm.find(vm.create_cache, "make").should eq(Regex::Automata::Match.must(0, 0...4))
  end

  it "compiles the same literals in reverse byte order without reversing priority" do
    trie = Regex::Automata::NFA::LiteralTrie.reverse
    ["make", "maple", "maker"].each { |literal| trie.add(literal.to_slice) }
    trie.inspect.lines[1].starts_with?("000000: e => 1, r => ").should be_true
    nfa = compile_vendor_literal_trie(["make", "maple", "maker"], reverse: true)
    nfa.is_reverse.should be_true
    vm = Regex::Automata::NFA::PikeVM.new_from_nfa(nfa)
    vm.find(vm.create_cache, "ekam").should eq(Regex::Automata::Match.must(0, 0...4))
  end
end
