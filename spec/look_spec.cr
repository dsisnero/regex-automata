require "./spec_helper"

private def matches_look(look : Regex::Automata::Look, haystack : String, at : Int32) : Bool
  Regex::Automata::LookMatcher.new.matches(look, haystack.to_slice, at)
end

describe Regex::Automata::Look do
  it "maps reverse assertions and display chars" do
    Regex::Automata::Look::Start.reversed.should eq(Regex::Automata::Look::End)
    Regex::Automata::Look::WordStartUnicode.reversed.should eq(Regex::Automata::Look::WordEndUnicode)
    Regex::Automata::Look::WordUnicode.reversed.should eq(Regex::Automata::Look::WordUnicode)
    Regex::Automata::Look::Start.as_char.should eq('A')
    Regex::Automata::Look::WordEndHalfUnicode.as_char.should eq('▶')
    Regex::Automata::Look.from_repr(Regex::Automata::Look::WordAscii.as_repr).should eq(Regex::Automata::Look::WordAscii)
  end
end

describe Regex::Automata::LookMatcher do
  it "matches start line" do
    look = Regex::Automata::Look::StartLF

    matches_look(look, "", 0).should be_true
    matches_look(look, "\n", 0).should be_true
    matches_look(look, "\n", 1).should be_true
    matches_look(look, "a", 0).should be_true
    matches_look(look, "\na", 1).should be_true

    matches_look(look, "a", 1).should be_false
    matches_look(look, "a\na", 1).should be_false
  end

  it "matches end line" do
    look = Regex::Automata::Look::EndLF

    matches_look(look, "", 0).should be_true
    matches_look(look, "\n", 1).should be_true
    matches_look(look, "\na", 0).should be_true
    matches_look(look, "\na", 2).should be_true
    matches_look(look, "a\na", 1).should be_true

    matches_look(look, "a", 0).should be_false
    matches_look(look, "\na", 1).should be_false
    matches_look(look, "a\na", 0).should be_false
    matches_look(look, "a\na", 2).should be_false
  end

  it "matches start text" do
    look = Regex::Automata::Look::Start

    matches_look(look, "", 0).should be_true
    matches_look(look, "\n", 0).should be_true
    matches_look(look, "a", 0).should be_true

    matches_look(look, "\n", 1).should be_false
    matches_look(look, "\na", 1).should be_false
    matches_look(look, "a", 1).should be_false
    matches_look(look, "a\na", 1).should be_false
  end

  it "matches end text" do
    look = Regex::Automata::Look::End

    matches_look(look, "", 0).should be_true
    matches_look(look, "\n", 1).should be_true
    matches_look(look, "\na", 2).should be_true

    matches_look(look, "\na", 0).should be_false
    matches_look(look, "a\na", 1).should be_false
    matches_look(look, "a", 0).should be_false
    matches_look(look, "\na", 1).should be_false
    matches_look(look, "a\na", 0).should be_false
    matches_look(look, "a\na", 2).should be_false
  end

  it "matches word unicode" do
    look = Regex::Automata::Look::WordUnicode

    matches_look(look, "a", 0).should be_true
    matches_look(look, "a", 1).should be_true
    matches_look(look, "a ", 1).should be_true
    matches_look(look, " a ", 1).should be_true
    matches_look(look, " a ", 2).should be_true

    matches_look(look, "𝛃", 0).should be_true
    matches_look(look, "𝛃", 4).should be_true
    matches_look(look, "𝛃 ", 4).should be_true
    matches_look(look, " 𝛃 ", 1).should be_true
    matches_look(look, " 𝛃 ", 5).should be_true

    matches_look(look, "𝛃𐆀", 0).should be_true
    matches_look(look, "𝛃𐆀", 4).should be_true

    matches_look(look, "", 0).should be_false
    matches_look(look, "ab", 1).should be_false
    matches_look(look, "a ", 2).should be_false
    matches_look(look, " a ", 0).should be_false
    matches_look(look, " a ", 3).should be_false

    matches_look(look, "𝛃b", 4).should be_false
    matches_look(look, "𝛃 ", 5).should be_false
    matches_look(look, " 𝛃 ", 0).should be_false
    matches_look(look, " 𝛃 ", 6).should be_false
    matches_look(look, "𝛃", 1).should be_false
    matches_look(look, "𝛃", 2).should be_false
    matches_look(look, "𝛃", 3).should be_false

    matches_look(look, "𝛃𐆀", 1).should be_false
    matches_look(look, "𝛃𐆀", 2).should be_false
    matches_look(look, "𝛃𐆀", 3).should be_false
    matches_look(look, "𝛃𐆀", 5).should be_false
    matches_look(look, "𝛃𐆀", 6).should be_false
    matches_look(look, "𝛃𐆀", 7).should be_false
    matches_look(look, "𝛃𐆀", 8).should be_false
  end

  it "matches word ascii" do
    look = Regex::Automata::Look::WordAscii

    matches_look(look, "a", 0).should be_true
    matches_look(look, "a", 1).should be_true
    matches_look(look, "a ", 1).should be_true
    matches_look(look, " a ", 1).should be_true
    matches_look(look, " a ", 2).should be_true

    matches_look(look, "𝛃", 0).should be_false
    matches_look(look, "𝛃", 4).should be_false
    matches_look(look, "𝛃 ", 4).should be_false
    matches_look(look, " 𝛃 ", 1).should be_false
    matches_look(look, " 𝛃 ", 5).should be_false

    matches_look(look, "𝛃𐆀", 0).should be_false
    matches_look(look, "𝛃𐆀", 4).should be_false

    matches_look(look, "", 0).should be_false
    matches_look(look, "ab", 1).should be_false
    matches_look(look, "a ", 2).should be_false
    matches_look(look, " a ", 0).should be_false
    matches_look(look, " a ", 3).should be_false

    matches_look(look, "𝛃b", 4).should be_true
    matches_look(look, "𝛃 ", 5).should be_false
    matches_look(look, " 𝛃 ", 0).should be_false
    matches_look(look, " 𝛃 ", 6).should be_false
    matches_look(look, "𝛃", 1).should be_false
    matches_look(look, "𝛃", 2).should be_false
    matches_look(look, "𝛃", 3).should be_false
  end

  it "matches word unicode negate" do
    look = Regex::Automata::Look::WordUnicodeNegate

    matches_look(look, "a", 0).should be_false
    matches_look(look, "a", 1).should be_false
    matches_look(look, "a ", 1).should be_false
    matches_look(look, " a ", 1).should be_false
    matches_look(look, " a ", 2).should be_false

    matches_look(look, "𝛃", 0).should be_false
    matches_look(look, "𝛃", 4).should be_false
    matches_look(look, "𝛃 ", 4).should be_false
    matches_look(look, " 𝛃 ", 1).should be_false
    matches_look(look, " 𝛃 ", 5).should be_false

    matches_look(look, "𝛃𐆀", 0).should be_false
    matches_look(look, "𝛃𐆀", 4).should be_false

    matches_look(look, "", 0).should be_true
    matches_look(look, "ab", 1).should be_true
    matches_look(look, "a ", 2).should be_true
    matches_look(look, " a ", 0).should be_true
    matches_look(look, " a ", 3).should be_true

    matches_look(look, "𝛃b", 4).should be_true
    matches_look(look, "𝛃 ", 5).should be_true
    matches_look(look, " 𝛃 ", 0).should be_true
    matches_look(look, " 𝛃 ", 6).should be_true
    matches_look(look, "𝛃", 1).should be_false
    matches_look(look, "𝛃", 2).should be_false
    matches_look(look, "𝛃", 3).should be_false

    matches_look(look, "𝛃𐆀", 1).should be_false
    matches_look(look, "𝛃𐆀", 2).should be_false
    matches_look(look, "𝛃𐆀", 3).should be_false
    matches_look(look, "𝛃𐆀", 5).should be_false
    matches_look(look, "𝛃𐆀", 6).should be_false
    matches_look(look, "𝛃𐆀", 7).should be_false
    matches_look(look, "𝛃𐆀", 8).should be_true
  end

  it "matches word ascii negate" do
    look = Regex::Automata::Look::WordAsciiNegate

    matches_look(look, "a", 0).should be_false
    matches_look(look, "a", 1).should be_false
    matches_look(look, "a ", 1).should be_false
    matches_look(look, " a ", 1).should be_false
    matches_look(look, " a ", 2).should be_false

    matches_look(look, "𝛃", 0).should be_true
    matches_look(look, "𝛃", 4).should be_true
    matches_look(look, "𝛃 ", 4).should be_true
    matches_look(look, " 𝛃 ", 1).should be_true
    matches_look(look, " 𝛃 ", 5).should be_true

    matches_look(look, "𝛃𐆀", 0).should be_true
    matches_look(look, "𝛃𐆀", 4).should be_true

    matches_look(look, "", 0).should be_true
    matches_look(look, "ab", 1).should be_true
    matches_look(look, "a ", 2).should be_true
    matches_look(look, " a ", 0).should be_true
    matches_look(look, " a ", 3).should be_true

    matches_look(look, "𝛃b", 4).should be_false
    matches_look(look, "𝛃 ", 5).should be_true
    matches_look(look, " 𝛃 ", 0).should be_true
    matches_look(look, " 𝛃 ", 6).should be_true
    matches_look(look, "𝛃", 1).should be_true
    matches_look(look, "𝛃", 2).should be_true
    matches_look(look, "𝛃", 3).should be_true
  end

  it "matches word start and end variants" do
    matcher = Regex::Automata::LookMatcher.new

    matcher.matches(Regex::Automata::Look::WordStartAscii, " a ".to_slice, 1).should be_true
    matcher.matches(Regex::Automata::Look::WordEndAscii, " a ".to_slice, 2).should be_true
    matcher.matches(Regex::Automata::Look::WordStartUnicode, " 𝛃 ".to_slice, 1).should be_true
    matcher.matches(Regex::Automata::Look::WordEndUnicode, " 𝛃 ".to_slice, 5).should be_true

    matcher.matches(Regex::Automata::Look::WordStartHalfAscii, "".to_slice, 0).should be_true
    matcher.matches(Regex::Automata::Look::WordEndHalfAscii, "".to_slice, 0).should be_true
    matcher.matches(Regex::Automata::Look::WordStartHalfUnicode, "𝛃𐆀".to_slice, 8).should be_true
    matcher.matches(Regex::Automata::Look::WordEndHalfUnicode, "𝛃𐆀".to_slice, 8).should be_true

    matcher.matches(Regex::Automata::Look::WordStartUnicode, "𝛃".to_slice, 1).should be_false
    matcher.matches(Regex::Automata::Look::WordEndUnicode, "𝛃".to_slice, 1).should be_false
    matcher.matches(Regex::Automata::Look::WordStartHalfUnicode, "𝛃".to_slice, 1).should be_false
    matcher.matches(Regex::Automata::Look::WordEndHalfUnicode, "𝛃".to_slice, 1).should be_false
  end

  it "supports custom line terminators and matches_set" do
    matcher = Regex::Automata::LookMatcher.new
    matcher.get_line_terminator.should eq('\n'.ord.to_u8)
    matcher = matcher.set_line_terminator(0_u8)
    matcher.get_line_terminator.should eq(0_u8)

    matcher.matches(Regex::Automata::Look::StartLF, "\0abc".to_slice, 1).should be_true
    matcher.matches(Regex::Automata::Look::EndLF, "abc\0".to_slice, 3).should be_true
    matcher.matches(Regex::Automata::Look::StartLF, "\nabc".to_slice, 1).should be_false

    set = Regex::Automata::LookSet.empty
      .insert(Regex::Automata::Look::StartLF)
      .insert(Regex::Automata::Look::WordAscii)
    matcher.matches_set(set, "\0a".to_slice, 1).should be_true
    matcher.matches_set(set, " a".to_slice, 1).should be_false
  end
end

describe Regex::Automata::LookSet do
  it "supports set operations and category predicates" do
    set = Regex::Automata::LookSet.empty
    set.empty?.should be_true
    set.is_empty.should be_true
    set.contains(Regex::Automata::Look::Start).should be_false

    set = set.insert(Regex::Automata::Look::Start)
    set.contains(Regex::Automata::Look::Start).should be_true
    set.contains_anchor.should be_true
    set.contains_anchor_haystack.should be_true
    set.contains_anchor_line.should be_false

    set = set.insert(Regex::Automata::Look::StartLF)
    set.contains_anchor_line.should be_true
    set.contains_anchor_lf.should be_true
    set.contains_anchor_crlf.should be_false

    set = set.insert(Regex::Automata::Look::StartCRLF)
    set.contains_anchor_crlf.should be_true

    set = set.insert(Regex::Automata::Look::WordUnicode)
    set.contains_word.should be_true
    set.contains_word_unicode.should be_true
    set.contains_word_ascii.should be_false

    other = Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordAscii)
    union = set.union(other)
    union.contains_word_ascii.should be_true
    union.includes?(Regex::Automata::Look::WordAscii).should be_true
    union.difference(other).contains(Regex::Automata::Look::WordAscii).should be_false
    union.intersect(other).contains(Regex::Automata::Look::WordAscii).should be_true
    union.symmetric_difference(other).contains(Regex::Automata::Look::WordAscii).should be_false
    union.superset?(other).should be_true
    other.subset?(union).should be_true

    mutable = Regex::Automata::LookSet.empty
    mutable.set_insert(Regex::Automata::Look::WordStartAscii)
    mutable.contains(Regex::Automata::Look::WordStartAscii).should be_true
    mutable.set_union(Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordEndAscii))
    mutable.contains(Regex::Automata::Look::WordEndAscii).should be_true
    mutable.set_intersect(Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordEndAscii))
    mutable.contains(Regex::Automata::Look::WordStartAscii).should be_false
    mutable.set_subtract(Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordEndAscii))
    mutable.empty?.should be_true
    mutable.set_insert(Regex::Automata::Look::WordUnicode)
    mutable.set_remove(Regex::Automata::Look::WordUnicode)
    mutable.empty?.should be_true
  end

  it "round trips repr io and availability" do
    set = Regex::Automata::LookSet.empty
      .insert(Regex::Automata::Look::StartLF)
      .insert(Regex::Automata::Look::WordUnicode)
    buffer = Bytes.new(4, 0_u8)
    set.write_repr(buffer)
    Regex::Automata::LookSet.read_repr(buffer).should eq(set)
    set.available.should be_nil
    Regex::Automata::UnicodeWordBoundaryError.check.should be_nil
  end

  it "iterates valid look assertions in order" do
    Regex::Automata::LookSet.empty.iter.to_a.should eq([] of Regex::Automata::Look)
    Regex::Automata::LookSet.full.iter.to_a.size.should eq(18)

    set = Regex::Automata::LookSet.empty
      .insert(Regex::Automata::Look::StartLF)
      .insert(Regex::Automata::Look::WordUnicode)
    set.iter.to_a.should eq([
      Regex::Automata::Look::StartLF,
      Regex::Automata::Look::WordUnicode,
    ])
  end

  it "renders debug glyphs" do
    Regex::Automata::LookSet.empty.inspect.should eq("∅")
    Regex::Automata::LookSet.full.inspect.should eq("Az^$rRbB𝛃𝚩<>〈〉◁▷◀▶")
  end
end
