require "./spec_helper"

describe Regex::Automata::Wire do
  it "uses vendored serialization error text" do
    Regex::Automata::SerializeError.buffer_too_small("bytes").message.should eq("destination buffer is too small to write bytes")
    Regex::Automata::DeserializeError.buffer_too_small("bytes").message.should eq("buffer is too small to read bytes")
    Regex::Automata::DeserializeError.invalid_usize("offset").message.should eq("offset is too big to fit in a usize")
    Regex::Automata::DeserializeError.version_mismatch(1_u32, 2_u32).message.should eq("unsupported version: expected version 1 but found version 2")
    Regex::Automata::DeserializeError.endian_mismatch(0xAB_u32, 0xCD_u32).message.not_nil!.should contain("expected 0xAB but got 0xCD")
    Regex::Automata::DeserializeError.alignment_mismatch(4, 0x123_u64).message.not_nil!.should contain("address 0x123")
    Regex::Automata::DeserializeError.arithmetic_overflow("state count").message.should eq("arithmetic overflow for state count")
  end
end
