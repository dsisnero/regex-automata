require "./spec_helper"

describe Regex::Automata::Wire do
  it "round trips labels with padding" do
    buf = Bytes.new(1024, 0_u8)

    nwrite = Regex::Automata::Wire.write_label("fooba", buf)
    nwrite.should eq(8)
    buf[0, nwrite].should eq("fooba\x00\x00\x00".to_slice)

    nread = Regex::Automata::Wire.read_label(buf, "fooba")
    nread.should eq(8)
  end

  it "rejects labels with interior nul bytes" do
    expect_raises(ArgumentError, "label must not contain NUL bytes") do
      Regex::Automata::Wire.write_label("foo\u0000bar", Bytes.new(1024, 0_u8))
    end
  end

  it "accepts labels up to 255 bytes" do
    Regex::Automata::Wire.write_label("z" * 255, Bytes.new(1024, 0_u8)).should be > 0
  end

  it "rejects labels longer than 255 bytes" do
    expect_raises(ArgumentError, "label must not be longer than 255 bytes") do
      Regex::Automata::Wire.write_label("z" * 256, Bytes.new(1024, 0_u8))
    end
  end

  it "computes 4-byte padding lengths" do
    Regex::Automata::Wire.padding_len(8).should eq(0)
    Regex::Automata::Wire.padding_len(9).should eq(3)
    Regex::Automata::Wire.padding_len(10).should eq(2)
    Regex::Automata::Wire.padding_len(11).should eq(1)
    Regex::Automata::Wire.padding_len(12).should eq(0)
    Regex::Automata::Wire.padding_len(13).should eq(3)
    Regex::Automata::Wire.padding_len(14).should eq(2)
    Regex::Automata::Wire.padding_len(15).should eq(1)
    Regex::Automata::Wire.padding_len(16).should eq(0)
  end

  it "reports label mismatch and short buffers cleanly" do
    buf = Bytes.new(8, 0_u8)
    Regex::Automata::Wire.write_label("fooba", buf)

    expect_raises(Regex::Automata::DeserializeError, /label mismatch/) do
      Regex::Automata::Wire.read_label(buf, "bar")
    end

    short = Bytes[0x66_u8, 0x6F_u8, 0x6F_u8]
    expect_raises(Regex::Automata::DeserializeError, /could not find NUL terminated label/) do
      Regex::Automata::Wire.read_label(short, "foo")
    end
  end
end
