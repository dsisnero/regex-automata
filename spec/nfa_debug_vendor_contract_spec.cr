require "./spec_helper"

# Pinned oracle: nfa/thompson/nfa.rs Debug impls for Transition, State and Inner.
describe "pinned Thompson debug rendering" do
  it "renders transitions and final-state variants with Rust's labels" do
    sid = Regex::Automata::StateID.new(2)
    pid = Regex::Automata::PatternID.new(0)
    trans = Regex::Automata::NFA::Transition.new('a'.ord.to_u8, 'z'.ord.to_u8, sid)
    trans.inspect.should eq("a-z => 2")
    Regex::Automata::NFA::ByteRange.new(trans).inspect.should eq("a-z => 2")
    Regex::Automata::NFA::Sparse.new([trans]).inspect.should eq("sparse(a-z => 2)")
    Regex::Automata::NFA::Union.new([sid, Regex::Automata::StateID.new(3)]).inspect.should eq("union(2, 3)")
    Regex::Automata::NFA::BinaryUnion.new(sid, sid).inspect.should eq("binary-union(2, 2)")
    Regex::Automata::NFA::Look.new(Regex::Automata::NFA::Look::Kind::WordBoundaryAscii, sid).inspect.should eq("WordAscii => 2")
    Regex::Automata::NFA::Capture.new(sid, pid, 0, 1).inspect.should eq("capture(pid=0, group=0, slot=1) => 2")
    Regex::Automata::NFA::Match.new(pid).inspect.should eq("MATCH(0)")
    Regex::Automata::NFA::Fail.new.inspect.should eq("FAIL")
    targets = Array(Regex::Automata::StateID).new(256, Regex::Automata::StateID::ZERO)
    targets['a'.ord] = sid
    Regex::Automata::NFA::Dense.new(targets).inspect.should eq("dense(a => 2)")
  end

  it "marks starts and prints byte classes in the Rust NFA layout" do
    rendered = Regex::Automata::NFA::NFA.never_match.inspect
    rendered.starts_with?("thompson::NFA(\n^000000: FAIL\n").should be_true
    rendered.includes?("transition equivalence classes: ByteClasses(").should be_true
    rendered.ends_with?(")\n").should be_true

    multi = Regex::Automata::NFA::NFA.new_many(["a", "b"]).inspect
    multi.includes?("START(000000): ").should be_true
    multi.includes?("START(000001): ").should be_true
  end
end
