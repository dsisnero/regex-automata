require "./spec_helper"

private def nfa_pid(id : Int32) : Regex::Automata::PatternID
  Regex::Automata::PatternID.new(id)
end

private def nfa_sid(id : Int32) : Regex::Automata::StateID
  Regex::Automata::StateID.new(id)
end

private def nfa_build(pattern : String, *, reverse : Bool = false, shrink : Bool = false,
                      captures : Regex::Automata::NFA::WhichCaptures = Regex::Automata::NFA::WhichCaptures::None) : Regex::Automata::NFA::NFA
  Regex::Automata::NFA::NFA.compiler
    .configure(
      Regex::Automata::NFA::NFA.config
        .which_captures(captures)
        .unanchored_prefix(false)
        .reverse(reverse)
        .shrink(shrink)
    )
    .build(pattern)
end

private def nfa_byte(byte : UInt8, next_id : Int32) : Regex::Automata::NFA::ByteRange
  Regex::Automata::NFA::ByteRange.new(
    Regex::Automata::NFA::Transition.new(byte, byte, nfa_sid(next_id))
  )
end

private def nfa_range(start_byte : UInt8, end_byte : UInt8, next_id : Int32) : Regex::Automata::NFA::ByteRange
  Regex::Automata::NFA::ByteRange.new(
    Regex::Automata::NFA::Transition.new(start_byte, end_byte, nfa_sid(next_id))
  )
end

private def nfa_sparse(transitions : Array(Tuple(UInt8, UInt8, Int32))) : Regex::Automata::NFA::Sparse
  Regex::Automata::NFA::Sparse.new(
    transitions.map do |start_byte, end_byte, next_id|
      Regex::Automata::NFA::Transition.new(start_byte, end_byte, nfa_sid(next_id))
    end
  )
end

private def nfa_match(pattern_id : Int32) : Regex::Automata::NFA::Match
  Regex::Automata::NFA::Match.new(nfa_pid(pattern_id))
end

private def nfa_cap(next_id : Int32, pattern_id : Int32, group_index : Int32, slot : Int32) : Regex::Automata::NFA::Capture
  Regex::Automata::NFA::Capture.new(nfa_sid(next_id), nfa_pid(pattern_id), group_index, slot)
end

private def nfa_fail : Regex::Automata::NFA::Fail
  Regex::Automata::NFA::Fail.new
end

describe "Thompson NFA representation parity" do
  it "ports exact empty and literal compiler states" do
    nfa_build("").states.should eq([
      nfa_match(0),
    ])

    nfa_build("a").states.should eq([
      nfa_byte('a'.ord.to_u8, 1),
      nfa_match(0),
    ])

    nfa_build("ab").states.should eq([
      nfa_byte('a'.ord.to_u8, 1),
      nfa_byte('b'.ord.to_u8, 2),
      nfa_match(0),
    ])

    nfa_build("☃").states.should eq([
      nfa_byte(0xE2_u8, 1),
      nfa_byte(0x98_u8, 2),
      nfa_byte(0x83_u8, 3),
      nfa_match(0),
    ])
  end

  it "ports exact ASCII class states, including ASCII-only Unicode HIR" do
    nfa_build("[a-z]").states.should eq([
      nfa_range('a'.ord.to_u8, 'z'.ord.to_u8, 1),
      nfa_match(0),
    ])

    nfa_build("[x-za-c]").states.should eq([
      nfa_sparse([
        {'a'.ord.to_u8, 'c'.ord.to_u8, 1},
        {'x'.ord.to_u8, 'z'.ord.to_u8, 1},
      ]),
      nfa_match(0),
    ])
  end

  it "ports exact capture-policy state shapes for implicit and none" do
    nfa_build("a(b)c", captures: Regex::Automata::NFA::WhichCaptures::Implicit).states.should eq([
      nfa_cap(1, 0, 0, 0),
      nfa_byte('a'.ord.to_u8, 2),
      nfa_byte('b'.ord.to_u8, 3),
      nfa_byte('c'.ord.to_u8, 4),
      nfa_cap(5, 0, 0, 1),
      nfa_match(0),
    ])

    nfa_build("a(b)c", captures: Regex::Automata::NFA::WhichCaptures::None).states.should eq([
      nfa_byte('a'.ord.to_u8, 1),
      nfa_byte('b'.ord.to_u8, 2),
      nfa_byte('c'.ord.to_u8, 3),
      nfa_match(0),
    ])
  end

  it "ports exact empty byte and Unicode class lowering" do
    config = Regex::Automata::NFA::NFA.config
      .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      .unanchored_prefix(false)

    byte_hir = Regex::Syntax::Hir::Hir.new(
      Regex::Syntax::Hir::CharClass.new(false, [] of Range(UInt8, UInt8))
    )
    unicode_hir = Regex::Syntax::Hir::Hir.new(
      Regex::Syntax::Hir::UnicodeClass.new(false, [] of Range(UInt32, UInt32))
    )

    compiler = Regex::Automata::NFA::NFA.compiler.configure(config)
    compiler.build_from_hir(byte_hir).states.should eq([nfa_fail, nfa_match(0)])
    compiler.build_from_hir(unicode_hir).states.should eq([nfa_fail, nfa_match(0)])
  end

  it "exposes transition, sparse-transition and epsilon helpers" do
    transition = Regex::Automata::NFA::Transition.new('b'.ord.to_u8, 'd'.ord.to_u8, nfa_sid(7))
    haystack = Bytes['a'.ord.to_u8, 'c'.ord.to_u8, 'z'.ord.to_u8]

    transition.matches(haystack, 1).should be_true
    transition.matches(haystack, 0).should be_false
    transition.matches(haystack, 9).should be_false
    transition.matches_byte('c'.ord.to_u8).should be_true
    transition.matches_byte('z'.ord.to_u8).should be_false
    transition.matches_unit(Regex::Automata::Unit.u8('d'.ord.to_u8)).should be_true
    transition.matches_unit(Regex::Automata::Unit.eoi(2)).should be_false

    sparse = nfa_sparse([
      {'a'.ord.to_u8, 'c'.ord.to_u8, 1},
      {'x'.ord.to_u8, 'z'.ord.to_u8, 2},
    ])
    sparse.matches(haystack, 0).should eq(nfa_sid(1))
    sparse.matches(haystack, 1).should eq(nfa_sid(1))
    sparse.matches(haystack, 2).should eq(nfa_sid(2))
    sparse.matches(haystack, 5).should be_nil
    sparse.matches_unit(Regex::Automata::Unit.u8('y'.ord.to_u8)).should eq(nfa_sid(2))
    sparse.matches_unit(Regex::Automata::Unit.eoi(3)).should be_nil

    nfa_byte('a'.ord.to_u8, 1).is_epsilon.should be_false
    sparse.is_epsilon.should be_false
    Regex::Automata::NFA::Look.new(Regex::Automata::NFA::Look::Kind::StartText, nfa_sid(1)).is_epsilon.should be_true
    Regex::Automata::NFA::BinaryUnion.new(nfa_sid(1), nfa_sid(2)).is_epsilon.should be_true
    nfa_cap(1, 0, 0, 0).is_epsilon.should be_true
    nfa_match(0).is_epsilon.should be_false
    nfa_fail.is_epsilon.should be_false
  end

  it "computes byte classes and memory usage from the final graph" do
    ascii = nfa_build("[x-za-c]")
    classes = ascii.byte_classes
    classes.get('a'.ord.to_u8).should eq(classes.get('z'.ord.to_u8))
    classes.get('A'.ord.to_u8).should_not eq(classes.get('a'.ord.to_u8))
    classes.alphabet_len.should eq(3)

    unicode = nfa_build("[α-δ🤙-🤞]")
    unicode.memory_usage.should be > ascii.memory_usage
    unicode.byte_classes.alphabet_len.should be > ascii.byte_classes.alphabet_len
  end
end
