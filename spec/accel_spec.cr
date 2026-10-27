require "./spec_helper"

describe "DFA accelerators" do
  # Pinned dfa/accel.rs::{find_fwd,find_rev} delegates to util/memchr.rs.
  # Rust's &haystack[at..] / &haystack[..at] panic for out-of-range offsets.
  it "ports bounded forward/reverse byte searches and offset panics" do
    haystack = Bytes[0_u8, 255_u8, 98_u8, 97_u8, 255_u8, 0_u8]
    {Bytes[255_u8], Bytes[97_u8, 255_u8], Bytes[97_u8, 98_u8, 255_u8]}.each do |needles|
      Regex::Automata.find_fwd(needles, haystack, 2).should eq({4, 3, 2}[needles.size - 1])
      Regex::Automata.find_rev(needles, haystack, 4).should eq(needles.size == 1 ? 1 : 3)
      Regex::Automata.find_fwd(needles, haystack, haystack.size).should be_nil
      Regex::Automata.find_rev(needles, haystack, 0).should be_nil
      expect_raises(IndexError) { Regex::Automata.find_fwd(needles, haystack, haystack.size + 1) }
      expect_raises(IndexError) { Regex::Automata.find_rev(needles, haystack, haystack.size + 1) }
    end
  end

  it "keeps Rust's invalid needle-count panic ahead of offset slicing" do
    haystack = Bytes[97_u8]
    expect_raises(Exception, /cannot find with empty needles/) do
      Regex::Automata.find_fwd(Bytes.empty, haystack, 2)
    end
    expect_raises(Exception, /cannot find with empty needles/) do
      Regex::Automata.find_rev(Bytes.empty, haystack, 2)
    end
    expect_raises(Exception, /invalid needles length: 4/) do
      Regex::Automata.find_fwd(Bytes[1_u8, 2_u8, 3_u8, 4_u8], haystack, 2)
    end
    expect_raises(Exception, /invalid needles length: 4/) do
      Regex::Automata.find_rev(Bytes[1_u8, 2_u8, 3_u8, 4_u8], haystack, 2)
    end
  end

  it "builds individual accelerators and searches for their bytes" do
    accel = Regex::Automata::Accel.empty
    accel.empty?.should be_true
    accel.len.should eq(0)

    accel.add('x'.ord.to_u8).should be_true
    accel.add('y'.ord.to_u8).should be_true
    accel.add(' '.ord.to_u8).should be_false
    accel.len.should eq(2)
    accel.empty?.should be_false
    accel.needles.to_a.should eq(['x'.ord.to_u8, 'y'.ord.to_u8])

    expect_raises(Exception, /already contains/) do
      accel.add('x'.ord.to_u8)
    end

    raw = Bytes[2_u8, 'x'.ord.to_u8, 'y'.ord.to_u8, 0_u8]
    roundtrip = Regex::Automata::Accel.from_slice(raw)
    roundtrip.should_not be_nil
    roundtrip.not_nil!.needles.to_a.should eq(['x'.ord.to_u8, 'y'.ord.to_u8])
    Regex::Automata::Accel.from_slice(Bytes[4_u8, 0_u8, 0_u8, 0_u8]).should be_nil

    haystack = "zzyx".to_slice
    Regex::Automata.find_fwd(accel.needles, haystack, 0).should eq(2)
    Regex::Automata.find_rev(accel.needles, haystack, haystack.size).should eq(3)
  end

  it "round-trips accelerator collections from bytes" do
    first = Regex::Automata::Accel.empty
    first.add('a'.ord.to_u8)

    second = Regex::Automata::Accel.empty
    second.add('x'.ord.to_u8)
    second.add('z'.ord.to_u8)

    accels = Regex::Automata::Accels.empty
    accels.add(first)
    accels.add(second)

    accels.len.should eq(2)
    accels.needles(0).to_a.should eq(['a'.ord.to_u8])
    accels.needles(1).to_a.should eq(['x'.ord.to_u8, 'z'.ord.to_u8])
    accels.validate.should be_true
    accels.write_to_len.should eq(accels.as_bytes.size)
    accels.memory_usage.should eq(accels.as_bytes.size)
    accels.as_ref.needles(1).to_a.should eq(['x'.ord.to_u8, 'z'.ord.to_u8])
    accels.to_owned.needles(0).to_a.should eq(['a'.ord.to_u8])

    decoded, bytes_read = Regex::Automata::Accels.from_bytes_unchecked(accels.as_bytes)
    bytes_read.should eq(accels.write_to_len)
    decoded.len.should eq(2)
    decoded.needles(0).to_a.should eq(['a'.ord.to_u8])
    decoded.needles(1).to_a.should eq(['x'.ord.to_u8, 'z'.ord.to_u8])
  end
end
