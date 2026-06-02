require "./spec_helper"

private def start_map
  Regex::Automata::StartByteMap.new(Regex::Automata::LookMatcher.new)
end

describe Regex::Automata::StartConfig do
  it "defaults to an unanchored text start and supports builder-style updates" do
    original = Regex::Automata::StartConfig.new
    updated = original
      .look_behind('x'.ord.to_u8)
      .anchored(Regex::Automata::Anchored::Yes)

    original.get_look_behind.should be_nil
    original.get_anchored.should eq(Regex::Automata::Anchored::No)

    updated.get_look_behind.should eq('x'.ord.to_u8)
    updated.get_anchored.should eq(Regex::Automata::Anchored::Yes)
  end

  it "derives a text start for forward done ranges" do
    input = Regex::Automata::Input.new("").span(1...0)
    config = Regex::Automata::StartConfig.from_input_forward(input)

    config.get_look_behind.try { |byte| start_map.get(byte) }.should eq(nil)
    (config.get_look_behind.try { |byte| start_map.get(byte) } || Regex::Automata::Start::Text).should eq(
      Regex::Automata::Start::Text
    )
  end

  it "derives a text start for reverse done ranges" do
    input = Regex::Automata::Input.new("").span(1...0)
    config = Regex::Automata::StartConfig.from_input_reverse(input)

    config.get_look_behind.try { |byte| start_map.get(byte) }.should eq(nil)
    (config.get_look_behind.try { |byte| start_map.get(byte) } || Regex::Automata::Start::Text).should eq(
      Regex::Automata::Start::Text
    )
  end

  it "derives forward start configurations from the byte before the span" do
    classify = ->(haystack : String, start : Int32, finish : Int32) do
      input = Regex::Automata::Input.new(haystack).span(start...finish)
      config = Regex::Automata::StartConfig.from_input_forward(input)
      config.get_look_behind.try { |byte| start_map.get(byte) } || Regex::Automata::Start::Text
    end

    classify.call("", 0, 0).should eq(Regex::Automata::Start::Text)
    classify.call("abc", 0, 3).should eq(Regex::Automata::Start::Text)
    classify.call("\nabc", 0, 3).should eq(Regex::Automata::Start::Text)
    classify.call("\nabc", 1, 3).should eq(Regex::Automata::Start::LineLF)
    classify.call("\rabc", 1, 3).should eq(Regex::Automata::Start::LineCR)
    classify.call("abc", 1, 3).should eq(Regex::Automata::Start::WordByte)
    classify.call(" abc", 1, 3).should eq(Regex::Automata::Start::NonWordByte)
  end

  it "derives reverse start configurations from the byte after the span" do
    classify = ->(haystack : String, start : Int32, finish : Int32) do
      input = Regex::Automata::Input.new(haystack).span(start...finish)
      config = Regex::Automata::StartConfig.from_input_reverse(input)
      config.get_look_behind.try { |byte| start_map.get(byte) } || Regex::Automata::Start::Text
    end

    classify.call("", 0, 0).should eq(Regex::Automata::Start::Text)
    classify.call("abc", 0, 3).should eq(Regex::Automata::Start::Text)
    classify.call("abc\n", 0, 4).should eq(Regex::Automata::Start::Text)
    classify.call("abc\nz", 0, 3).should eq(Regex::Automata::Start::LineLF)
    classify.call("abc\rz", 0, 3).should eq(Regex::Automata::Start::LineCR)
    classify.call("abc", 0, 2).should eq(Regex::Automata::Start::WordByte)
    classify.call("abc ", 0, 3).should eq(Regex::Automata::Start::NonWordByte)
  end
end
