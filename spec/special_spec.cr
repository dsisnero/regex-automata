require "./spec_helper"

describe Regex::Automata::Special do
  it "keeps dead state distinct from absent special ranges" do
    special = Regex::Automata::Special.new
    dead = Regex::Automata::DEAD_STATE_ID

    special.is_special_state?(dead).should be_true
    special.is_dead_state?(dead).should be_true
    special.is_quit_state?(dead).should be_false
    special.is_match_state?(dead).should be_false
    special.is_accel_state?(dead).should be_false
    special.is_start_state?(dead).should be_false
    special.matches?.should be_false
    special.accels?.should be_false
    special.starts?.should be_false
  end

  it "counts premultiplied special-state ranges by stride" do
    special = Regex::Automata::Special.new
    special.set_quit_id(Regex::Automata::StateID.new(4))
    special.add_match(Regex::Automata::StateID.new(8))
    special.add_match(Regex::Automata::StateID.new(16))
    special.add_accel(Regex::Automata::StateID.new(12))
    special.add_accel(Regex::Automata::StateID.new(16))
    special.add_start(Regex::Automata::StateID.new(20))

    special.is_quit_state?(Regex::Automata::StateID.new(4)).should be_true
    special.is_match_state?(Regex::Automata::StateID.new(8)).should be_true
    special.is_match_state?(Regex::Automata::StateID.new(12)).should be_true
    special.is_accel_state?(Regex::Automata::StateID.new(12)).should be_true
    special.is_start_state?(Regex::Automata::StateID.new(20)).should be_true
    special.match_len(4).should eq(3)
    special.accel_len(4).should eq(2)
    special.start_len(4).should eq(1)
  end

  it "uses a fixed-width special-state wire representation" do
    special = Regex::Automata::Special.new
    special.set_quit_id(Regex::Automata::StateID.new(1))
    buffer = Bytes.new(special.write_to_len)

    special.write_to(buffer).should eq(special.write_to_len)
    restored = Regex::Automata::Special.from_bytes(buffer).not_nil!
    restored.quit_id.should eq(Regex::Automata::StateID.new(1))
    expect_raises(Regex::Automata::SerializeError) do
      special.write_to(Bytes.new(special.write_to_len - 1))
    end
  end

  it "rejects malformed special-state ranges" do
    invalid = Regex::Automata::Special.new(
      Regex::Automata::StateID.new(1),
      Regex::Automata::StateID.new(1),
      Regex::Automata::StateID.new(0),
      Regex::Automata::StateID.new(1),
      Regex::Automata::StateID.new(0),
      Regex::Automata::StateID.new(0),
      Regex::Automata::StateID.new(0),
      Regex::Automata::StateID.new(0)
    )
    invalid.validate.not_nil!.message.not_nil!.should contain("min_match is DEAD")

    valid = Regex::Automata::Special.new
    valid.set_quit_id(Regex::Automata::StateID.new(4))
    valid.validate_state_len(1, 2).not_nil!.message.not_nil!.should contain("max should")
    valid.validate_state_len(2, 2).should be_nil
  end
end
