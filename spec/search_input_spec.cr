require "./spec_helper"

describe Regex::Automata::Input do
  it "defaults to the entire haystack with unanchored, non-earliest search" do
    input = Regex::Automata::Input.new("foobar")
    span = input.get_span

    input.haystack.should eq("foobar".to_slice)
    input.start.should eq(0)
    input.end.should eq(6)
    span.should eq(Regex::Automata::Span.new(0, 6))
    span.range.should eq(0...6)
    input.get_range.should eq(0...6)
    input.get_anchored.should eq(Regex::Automata::Anchored::No)
    input.get_earliest.should be_false
    input.is_done.should be_false
  end

  it "supports builder-style span, range, anchored, and earliest updates" do
    input = Regex::Automata::Input.new("foobar")
      .span(1...4)
      .range(2..4)
      .anchored(Regex::Automata::Anchored::Yes)
      .earliest(true)

    input.start.should eq(2)
    input.end.should eq(5)
    input.get_range.should eq(2...5)
    input.get_anchored.should eq(Regex::Automata::Anchored::Yes)
    input.get_earliest.should be_true
  end

  it "supports in-place setters for span-derived state" do
    input = Regex::Automata::Input.new("foobar")

    input.set_span(1...4)
    input.get_range.should eq(1...4)

    input.set_range(2..4)
    input.get_range.should eq(2...5)

    input.set_start(4)
    input.get_range.should eq(4...5)

    input.set_end(4)
    input.get_range.should eq(4...4)

    input.set_anchored(Regex::Automata::Anchored::Yes)
    input.get_anchored.should eq(Regex::Automata::Anchored::Yes)

    input.set_earliest(true)
    input.get_earliest.should be_true
  end

  it "permits the upstream done-state sentinel and rejects spans beyond it" do
    input = Regex::Automata::Input.new("foobar")

    input.set_start(7)
    input.is_done.should be_true
    input.start.should eq(7)
    input.end.should eq(6)

    expect_raises(ArgumentError, /invalid span/) do
      input.set_start(8)
    end
  end

  it "reports UTF-8 codepoint boundaries relative to the haystack" do
    input = Regex::Automata::Input.new("☃")

    input.is_char_boundary(0).should be_true
    input.is_char_boundary(1).should be_false
    input.is_char_boundary(2).should be_false
    input.is_char_boundary(3).should be_true
    input.is_char_boundary(4).should be_false
  end
end
