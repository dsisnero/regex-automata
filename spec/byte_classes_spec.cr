require "./spec_helper"

describe Regex::Automata::ByteClasses do
  it "ports upstream byte class partitioning" do
    set = Regex::Automata::ByteClassSet.empty
    set.set_range('a'.ord.to_u8, 'z'.ord.to_u8)

    classes = set.byte_classes
    classes.get(0_u8).should eq(0_u8)
    classes.get(1_u8).should eq(0_u8)
    classes.get(('a'.ord - 1).to_u8).should eq(0_u8)
    classes.get('a'.ord.to_u8).should eq(1_u8)
    classes.get('m'.ord.to_u8).should eq(1_u8)
    classes.get('z'.ord.to_u8).should eq(1_u8)
    classes.get(('z'.ord + 1).to_u8).should eq(2_u8)
    classes.get(255_u8).should eq(2_u8)

    set = Regex::Automata::ByteClassSet.empty
    set.set_range(0_u8, 2_u8)
    set.set_range(4_u8, 6_u8)
    classes = set.byte_classes
    classes.get(0_u8).should eq(0_u8)
    classes.get(2_u8).should eq(0_u8)
    classes.get(3_u8).should eq(1_u8)
    classes.get(4_u8).should eq(2_u8)
    classes.get(6_u8).should eq(2_u8)
    classes.get(7_u8).should eq(3_u8)
    classes.get(255_u8).should eq(3_u8)
  end

  it "ports upstream full byte classes" do
    set = Regex::Automata::ByteClassSet.empty
    (0_u8..255_u8).each { |byte| set.set_range(byte, byte) }
    set.byte_classes.alphabet_len.should eq(257)
  end

  it "ports upstream class elements for typical partitions" do
    set = Regex::Automata::ByteClassSet.empty
    set.set_range('b'.ord.to_u8, 'd'.ord.to_u8)
    set.set_range('g'.ord.to_u8, 'm'.ord.to_u8)
    set.set_range('z'.ord.to_u8, 'z'.ord.to_u8)
    classes = set.byte_classes
    classes.alphabet_len.should eq(8)

    elements = classes.elements(Regex::Automata::Unit.u8(0_u8)).to_a
    elements.size.should eq(98)
    elements.first.should eq(Regex::Automata::Unit.u8(0_u8))
    elements.last.should eq(Regex::Automata::Unit.u8('a'.ord.to_u8))

    classes.elements(Regex::Automata::Unit.u8(1_u8)).to_a.should eq([
      Regex::Automata::Unit.u8('b'.ord.to_u8),
      Regex::Automata::Unit.u8('c'.ord.to_u8),
      Regex::Automata::Unit.u8('d'.ord.to_u8),
    ])

    classes.elements(Regex::Automata::Unit.u8(2_u8)).to_a.should eq([
      Regex::Automata::Unit.u8('e'.ord.to_u8),
      Regex::Automata::Unit.u8('f'.ord.to_u8),
    ])

    classes.elements(Regex::Automata::Unit.u8(5_u8)).to_a.should eq([
      Regex::Automata::Unit.u8('z'.ord.to_u8),
    ])

    classes.elements(Regex::Automata::Unit.eoi(7)).to_a.should eq([
      Regex::Automata::Unit.eoi(256),
    ])
  end

  it "ports upstream class elements for singleton and empty maps" do
    classes = Regex::Automata::ByteClasses.singletons
    classes.alphabet_len.should eq(257)
    classes.elements(Regex::Automata::Unit.u8('a'.ord.to_u8)).to_a.should eq([
      Regex::Automata::Unit.u8('a'.ord.to_u8),
    ])
    classes.elements(Regex::Automata::Unit.eoi(5)).to_a.should eq([
      Regex::Automata::Unit.eoi(256),
    ])

    classes = Regex::Automata::ByteClasses.empty
    classes.alphabet_len.should eq(2)
    elements = classes.elements(Regex::Automata::Unit.u8(0_u8)).to_a
    elements.size.should eq(256)
    elements.first.should eq(Regex::Automata::Unit.u8(0_u8))
    elements.last.should eq(Regex::Automata::Unit.u8(255_u8))
    classes.elements(Regex::Automata::Unit.eoi(1)).to_a.should eq([
      Regex::Automata::Unit.eoi(256),
    ])
  end

  it "ports upstream representatives with bounded and unbounded ranges" do
    set = Regex::Automata::ByteClassSet.empty
    set.set_range('b'.ord.to_u8, 'd'.ord.to_u8)
    set.set_range('g'.ord.to_u8, 'm'.ord.to_u8)
    set.set_range('z'.ord.to_u8, 'z'.ord.to_u8)
    classes = set.byte_classes

    classes.representatives.to_a.should eq([
      Regex::Automata::Unit.u8(0_u8),
      Regex::Automata::Unit.u8('b'.ord.to_u8),
      Regex::Automata::Unit.u8('e'.ord.to_u8),
      Regex::Automata::Unit.u8('g'.ord.to_u8),
      Regex::Automata::Unit.u8('n'.ord.to_u8),
      Regex::Automata::Unit.u8('z'.ord.to_u8),
      Regex::Automata::Unit.u8('{'.ord.to_u8),
      Regex::Automata::Unit.eoi(7),
    ])

    classes.representatives(0, 0).to_a.should eq([] of Regex::Automata::Unit)
    classes.representatives(1, 1).to_a.should eq([] of Regex::Automata::Unit)
    classes.representatives(255, 255).to_a.should eq([] of Regex::Automata::Unit)

    classes.representatives(256).to_a.should eq([
      Regex::Automata::Unit.eoi(7),
    ])

    classes.representatives(0, 255, inclusive_end: true, include_eoi: false).to_a.should eq([
      Regex::Automata::Unit.u8(0_u8),
      Regex::Automata::Unit.u8('b'.ord.to_u8),
      Regex::Automata::Unit.u8('e'.ord.to_u8),
      Regex::Automata::Unit.u8('g'.ord.to_u8),
      Regex::Automata::Unit.u8('n'.ord.to_u8),
      Regex::Automata::Unit.u8('z'.ord.to_u8),
      Regex::Automata::Unit.u8('{'.ord.to_u8),
    ])

    classes.representatives('b'.ord, 'd'.ord, inclusive_end: true, include_eoi: false).to_a.should eq([
      Regex::Automata::Unit.u8('b'.ord.to_u8),
    ])
    classes.representatives('a'.ord, 'd'.ord, inclusive_end: true, include_eoi: false).to_a.should eq([
      Regex::Automata::Unit.u8('a'.ord.to_u8),
      Regex::Automata::Unit.u8('b'.ord.to_u8),
    ])
    classes.representatives('b'.ord, 'e'.ord, inclusive_end: true, include_eoi: false).to_a.should eq([
      Regex::Automata::Unit.u8('b'.ord.to_u8),
      Regex::Automata::Unit.u8('e'.ord.to_u8),
    ])
    classes.representatives('A'.ord, 'Z'.ord, inclusive_end: true, include_eoi: false).to_a.should eq([
      Regex::Automata::Unit.u8('A'.ord.to_u8),
    ])
    classes.representatives('A'.ord, 'z'.ord, inclusive_end: true, include_eoi: false).to_a.should eq([
      Regex::Automata::Unit.u8('A'.ord.to_u8),
      Regex::Automata::Unit.u8('b'.ord.to_u8),
      Regex::Automata::Unit.u8('e'.ord.to_u8),
      Regex::Automata::Unit.u8('g'.ord.to_u8),
      Regex::Automata::Unit.u8('n'.ord.to_u8),
      Regex::Automata::Unit.u8('z'.ord.to_u8),
    ])
    classes.representatives('z'.ord).to_a.should eq([
      Regex::Automata::Unit.u8('z'.ord.to_u8),
      Regex::Automata::Unit.u8('{'.ord.to_u8),
      Regex::Automata::Unit.eoi(7),
    ])
    classes.representatives('z'.ord, 255, inclusive_end: true, include_eoi: false).to_a.should eq([
      Regex::Automata::Unit.u8('z'.ord.to_u8),
      Regex::Automata::Unit.u8('{'.ord.to_u8),
    ])
  end
end

describe Regex::Automata::Utf8 do
  it "matches upstream word-byte classification" do
    Regex::Automata::Utf8.is_word_byte('a'.ord.to_u8).should be_true
    Regex::Automata::Utf8.is_word_byte('Z'.ord.to_u8).should be_true
    Regex::Automata::Utf8.is_word_byte('0'.ord.to_u8).should be_true
    Regex::Automata::Utf8.is_word_byte('_'.ord.to_u8).should be_true
    Regex::Automata::Utf8.is_word_byte('-'.ord.to_u8).should be_false
  end

  it "decodes forward and reverse utf8 like upstream util::utf8" do
    Regex::Automata::Utf8.decode("".to_slice).should be_nil
    Regex::Automata::Utf8.decode("a".to_slice).should eq('a')
    Regex::Automata::Utf8.decode("β".to_slice).should eq('β')
    Regex::Automata::Utf8.decode(Bytes[0xFF_u8, 0x61_u8]).should eq(0xFF_u8)
    Regex::Automata::Utf8.decode(Bytes[0xCE_u8]).should eq(0xCE_u8)

    Regex::Automata::Utf8.decode_last("".to_slice).should be_nil
    Regex::Automata::Utf8.decode_last("a".to_slice).should eq('a')
    Regex::Automata::Utf8.decode_last("β".to_slice).should eq('β')
    Regex::Automata::Utf8.decode_last(Bytes[0x61_u8, 0xFF_u8]).should eq(0xFF_u8)
    Regex::Automata::Utf8.decode_last(Bytes[0xCE_u8]).should eq(0xCE_u8)
  end

  it "checks utf8 boundaries" do
    bytes = "βa".to_slice
    Regex::Automata::Utf8.is_boundary(bytes, 0).should be_true
    Regex::Automata::Utf8.is_boundary(bytes, 1).should be_false
    Regex::Automata::Utf8.is_boundary(bytes, 2).should be_true
    Regex::Automata::Utf8.is_boundary(bytes, 3).should be_true
    Regex::Automata::Utf8.is_boundary(bytes, 4).should be_false
  end
end

describe Regex::Automata::Utf8Sequences do
  it "enumerates ascii and non-ascii scalar ranges as utf8 byte automata" do
    ascii = Regex::Automata::Utf8Sequences.new('a', 'c')
    ascii.next.not_nil!.ranges.should eq([
      Regex::Automata::Utf8Range.new('a'.ord.to_u8, 'c'.ord.to_u8),
    ])
    ascii.next.should be_nil

    unicode = Regex::Automata::Utf8Sequences.new('β', 'δ')
    sequences = [] of Regex::Automata::Utf8Sequence
    while seq = unicode.next
      sequences << seq
    end

    sequences.should_not be_empty
    sequences.all? { |seq| seq.size >= 2 }.should be_true
    sequences.any? { |seq| seq.matches("β".to_slice) }.should be_true
    sequences.any? { |seq| seq.matches("γ".to_slice) }.should be_true
    sequences.any? { |seq| seq.matches("δ".to_slice) }.should be_true
  end
end
