require "./spec_helper"

describe "debug escaping" do
  it "formats bytes as readable debug escapes" do
    Regex::Automata::DebugByte.new(' '.ord.to_u8).inspect.should eq("' '")
    Regex::Automata::DebugByte.new('A'.ord.to_u8).inspect.should eq("A")
    Regex::Automata::DebugByte.new('\n'.ord.to_u8).inspect.should eq("\\n")
    Regex::Automata::DebugByte.new(0xFF_u8).inspect.should eq("\\xFF")
  end

  it "formats haystacks as quoted mostly-utf8 strings" do
    Regex::Automata::DebugHaystack.new("a\t☃".to_slice).inspect.should eq("\"a\\t☃\"")

    bytes = Bytes[0x66_u8, 0x6F_u8, 0x80_u8, 0x0A_u8]
    Regex::Automata::DebugHaystack.new(bytes).inspect.should eq("\"fo\\x80\\n\"")
  end
end
