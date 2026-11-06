require "./spec_helper"

# compiler.rs::Compiler retains Builder, Utf8State, RangeTrie, and
# Utf8SuffixMap, clearing their contents between compilations/classes.
class Regex::Automata::HirCompiler
  def vendor_builder_id : UInt64
    @builder.object_id
  end

  def vendor_unicode_scratch_ids : Tuple(UInt64, UInt64, UInt64)
    @builder.vendor_unicode_scratch_ids
  end
end

class Regex::Automata::NFA::Builder
  def vendor_unicode_scratch_ids : Tuple(UInt64, UInt64, UInt64)
    {@utf8_state.object_id, @range_trie.object_id, @utf8_suffix.object_id}
  end

  def vendor_compiler_match_count : Int32
    @states.count { |state| state.is_a?(Match) }.to_i32
  end

  def vendor_compiler_state_count : Int32
    @states.size.to_i32
  end
end

class Regex::Automata::HirCompiler
  def vendor_compiler_match_count : Int32
    @builder.vendor_compiler_match_count
  end

  def vendor_compiler_state_count : Int32
    @builder.vendor_compiler_state_count
  end
end

# Pinned compiler.rs::Compiler::compile sets Builder configuration before
# compiling even an empty expression list. c_alt_iter then emits Fail.
describe "pinned Thompson compiler empty-list configuration" do
  it "retains default UTF-8 mode for an empty pattern list" do
    nfa = Regex::Automata::NFA::NFA.compiler.build_many([] of String)
    nfa.pattern_len.should eq(0)
    nfa.is_utf8.should be_true
    nfa.is_reverse.should be_false
    nfa.has_empty.should be_false
  end

  it "retains reverse and look-matcher configuration for an empty HIR list" do
    matcher = Regex::Automata::LookMatcher.new
    matcher.set_line_terminator(0_u8)
    config = Regex::Automata::NFA::NFA.config
      .reverse(true)
      .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      .look_matcher(matcher)
    nfa = Regex::Automata::NFA::NFA.compiler.configure(config)
      .build_many_from_hir([] of Regex::Syntax::Hir::Hir)
    nfa.pattern_len.should eq(0)
    nfa.is_utf8.should be_true
    nfa.is_reverse.should be_true
    nfa.look_matcher.get_line_terminator.should eq(0_u8)
  end

  it "retains configuration in the Crystal compile_multi adapter too" do
    config = Regex::Automata::NFA::NFA.config
      .reverse(true)
      .which_captures(Regex::Automata::NFA::WhichCaptures::None)
    nfa = Regex::Automata::NFA::NFA.compiler.configure(config)
      .compile_multi([] of Regex::Syntax::Hir::Hir)
    nfa.is_utf8.should be_true
    nfa.is_reverse.should be_true
  end
end

describe "pinned Thompson compiler workspace reuse" do
  it "retains builder and Unicode scratch allocations without mutating earlier NFAs" do
    compiler = Regex::Automata::NFA::NFA.compiler
    builder_id = compiler.vendor_builder_id
    scratch_ids = compiler.vendor_unicode_scratch_ids

    first = compiler.build("[αβ][γδ]")
    first_graph = first.states.map(&.inspect)
    compiler.build("[εζ][ηθ]")

    compiler.vendor_builder_id.should eq(builder_id)
    compiler.vendor_unicode_scratch_ids.should eq(scratch_ids)
    first.states.map(&.inspect).should eq(first_graph)
  end
end

describe "pinned Thompson compiler terminal Match lowering" do
  it "patches repetition through Empty placeholders, as compiler.rs does" do
    compiler = Regex::Automata::NFA::NFA.compiler
    compiler.build("a+")
    compiler.vendor_compiler_match_count.should eq(1)
  end

  it "keeps Match terminal, with no Crystal-only next edge" do
    Regex::Automata::NFA::Match.new(Regex::Automata::PatternID::ZERO).responds_to?(:next).should be_false
  end

  it "does not allocate a spare Match for each literal byte" do
    compiler = Regex::Automata::NFA::NFA.compiler
    compiler.build("a")
    # Rust retains: prefix UnionReverse, Empty end, consuming Sparse,
    # implicit start, literal byte, implicit end, and one terminal Match.
    compiler.vendor_compiler_state_count.should eq(7)
    compiler.vendor_compiler_match_count.should eq(1)
  end

  it "lowers look assertions directly to patchable states" do
    compiler = Regex::Automata::NFA::NFA.compiler
    compiler.build("^")
    # The anchored prefix is a temporary Empty in Rust, removed at build.
    compiler.vendor_compiler_state_count.should eq(5)
  end
end

describe "pinned Rust Hir::dot normalization" do
  it "compiles every Crystal raw dot variant as Rust's smart-constructor class" do
    kinds = [
      Regex::Syntax::Hir::Dot::AnyChar,
      Regex::Syntax::Hir::Dot::AnyCharExceptLF,
      Regex::Syntax::Hir::Dot::AnyCharExceptCRLF,
      Regex::Syntax::Hir::Dot::AnyByte,
      Regex::Syntax::Hir::Dot::AnyByteExceptLF,
      Regex::Syntax::Hir::Dot::AnyByteExceptCRLF,
    ]
    kinds.each do |kind|
      raw = Regex::Syntax::Hir::Hir.new(Regex::Syntax::Hir::DotNode.new(kind))
      normalized = Regex::Syntax::Hir::Hir.dot(kind)
      {false, true}.each do |reverse|
        config = Regex::Automata::NFA::NFA.config
          .reverse(reverse)
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
        raw_nfa = Regex::Automata::NFA::NFA.compiler.configure(config).build_from_hir(raw)
        normalized_nfa = Regex::Automata::NFA::NFA.compiler.configure(config).build_from_hir(normalized)
        raw_nfa.states.map(&.inspect).should eq(normalized_nfa.states.map(&.inspect))
      end
    end
  end
end
