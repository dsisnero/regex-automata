require "./spec_helper"

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
end
