require "./spec_helper"

describe Regex::Automata::MatchError do
  it "preserves quit constructor state and kind" do
    error = Regex::Automata::MatchError.quit('x'.ord.to_u8, 7)

    error.kind.should eq(Regex::Automata::MatchError::Kind::Quit)
    error.byte.should eq('x'.ord.to_u8)
    error.offset.should eq(7)
    error.len.should be_nil
    error.mode.should be_nil
    error.quit?.should be_true
    error.gave_up?.should be_false
    error.haystack_too_long?.should be_false
    error.unsupported_anchored?.should be_false
    error.message.should eq("quit search after observing byte 120 at offset 7")
  end

  it "preserves gave-up constructor state and kind" do
    error = Regex::Automata::MatchError.gave_up(11)

    error.kind.should eq(Regex::Automata::MatchError::Kind::GaveUp)
    error.byte.should be_nil
    error.offset.should eq(11)
    error.len.should be_nil
    error.mode.should be_nil
    error.gave_up?.should be_true
    error.message.should eq("gave up searching at offset 11")
  end

  it "preserves haystack-too-long constructor state and kind" do
    error = Regex::Automata::MatchError.haystack_too_long(99)

    error.kind.should eq(Regex::Automata::MatchError::Kind::HaystackTooLong)
    error.byte.should be_nil
    error.offset.should be_nil
    error.len.should eq(99)
    error.mode.should be_nil
    error.haystack_too_long?.should be_true
    error.message.should eq("haystack of length 99 is too long")
  end

  it "preserves unsupported-anchored constructor state and kind" do
    error = Regex::Automata::MatchError.unsupported_anchored(Regex::Automata::Anchored::Yes)

    error.kind.should eq(Regex::Automata::MatchError::Kind::UnsupportedAnchored)
    error.byte.should be_nil
    error.offset.should be_nil
    error.len.should be_nil
    error.mode.should eq(Regex::Automata::Anchored::Yes)
    error.unsupported_anchored?.should be_true
    error.message.should eq("anchored searches are not supported or enabled")
  end

  it "uses distinct unsupported-anchored messages for each anchored mode" do
    Regex::Automata::MatchError
      .unsupported_anchored(Regex::Automata::Anchored::No)
      .message
      .should eq("unanchored searches are not supported or enabled")

    Regex::Automata::MatchError
      .unsupported_anchored(Regex::Automata::Anchored::Pattern)
      .message
      .should eq("anchored searches for a specific pattern are not supported or enabled")
  end

  it "includes the specific pattern id when available" do
    error = Regex::Automata::MatchError.unsupported_anchored(
      Regex::Automata::Anchored::Pattern,
      Regex::Automata::PatternID.new(3)
    )

    error.message.should eq(
      "anchored searches for a specific pattern (3) are not supported or enabled"
    )
  end
end
