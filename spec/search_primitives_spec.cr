require "./spec_helper"

describe "search result primitives" do
  it "reports anchored modes consistently" do
    Regex::Automata::Anchored::No.is_anchored.should be_false
    Regex::Automata::Anchored::Yes.is_anchored.should be_true
    Regex::Automata::Anchored::Pattern.is_anchored.should be_true
  end

  it "preserves half match pattern and offset" do
    match = Regex::Automata::HalfMatch.must(3, 12)

    match.pattern.should eq(Regex::Automata::PatternID.new(3))
    match.offset.should eq(12)
  end

  it "preserves full match span helpers" do
    match = Regex::Automata::Match.must(2, 5...10)

    match.pattern.should eq(Regex::Automata::PatternID.new(2))
    match.start.should eq(5)
    match.end.should eq(10)
    match.span.should eq(5...10)
    match.length.should eq(5)
    match.empty?.should be_false

    empty = Regex::Automata::Match.must(1, 8...8)
    empty.empty?.should be_true
    empty.length.should eq(0)
  end

  it "preserves span range and offset helpers" do
    span = Regex::Automata::Span.new(4, 9)

    span.range.should eq(4...9)
    span.empty?.should be_false
    span.length.should eq(5)
    span.contains?(4).should be_true
    span.contains?(8).should be_true
    span.contains?(9).should be_false
    span.offset(3).should eq(Regex::Automata::Span.new(7, 12))

    empty = Regex::Automata::Span.new(6, 6)
    empty.empty?.should be_true
    empty.length.should eq(0)
  end
end
