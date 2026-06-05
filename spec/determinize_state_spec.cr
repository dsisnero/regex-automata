require "./spec_helper"

describe Regex::Automata::Determinize::State do
  it "round trips representative NFA state IDs" do
    builder = Regex::Automata::Determinize::StateBuilderEmpty.new
      .into_matches
      .into_nfa
    [1, 3, 300, 301].each do |id|
      builder.add_nfa_state_id(Regex::Automata::StateID.new_unchecked(id))
    end

    state = builder.to_state
    got = [] of Regex::Automata::StateID
    state.iter_nfa_state_ids { |sid| got << sid }

    got.should eq([
      Regex::Automata::StateID.new_unchecked(1),
      Regex::Automata::StateID.new_unchecked(3),
      Regex::Automata::StateID.new_unchecked(300),
      Regex::Automata::StateID.new_unchecked(301),
    ])
  end

  it "round trips representative pattern IDs" do
    builder = Regex::Automata::Determinize::StateBuilderEmpty.new.into_matches
    [0, 5, 9].each do |id|
      builder.add_match_pattern_id(Regex::Automata::PatternID.new_unchecked(id))
    end

    state = builder.into_nfa.to_state
    state.match_len.should eq(3)
    state.match_pattern_ids.should eq([
      Regex::Automata::PatternID::ZERO,
      Regex::Automata::PatternID.new_unchecked(5),
      Regex::Automata::PatternID.new_unchecked(9),
    ])
  end

  it "optimizes a lone zero pattern ID" do
    builder = Regex::Automata::Determinize::StateBuilderEmpty.new.into_matches
    builder.add_match_pattern_id(Regex::Automata::PatternID::ZERO)

    state = builder.into_nfa.to_state
    state.is_match?.should be_true
    state.match_len.should eq(1)
    state.match_pattern(0).should eq(Regex::Automata::PatternID::ZERO)
    state.memory_usage.should eq(9)
  end

  it "tracks flags and look sets" do
    builder = Regex::Automata::Determinize::StateBuilderEmpty.new.into_matches
    builder.set_is_from_word
    builder.set_is_half_crlf
    builder.set_look_have { |set| set.insert(Regex::Automata::Look::WordAscii) }

    nfa = builder.into_nfa
    nfa.set_look_need { |set| set.insert(Regex::Automata::Look::Start) }
    nfa.add_nfa_state_id(Regex::Automata::StateID.new_unchecked(7))
    state = nfa.to_state

    state.is_from_word?.should be_true
    state.is_half_crlf?.should be_true
    state.look_have.should eq(
      Regex::Automata::LookSet.singleton(Regex::Automata::Look::WordAscii)
    )
    state.look_need.should eq(
      Regex::Automata::LookSet.singleton(Regex::Automata::Look::Start)
    )
  end
end

describe Regex::Automata::Determinize do
  it "round trips representative unsigned varints" do
    [0_u32, 1_u32, 127_u32, 128_u32, 255_u32, 16_384_u32, UInt32::MAX].each do |n|
      buffer = [] of UInt8
      Regex::Automata::Determinize.write_varu32(buffer, n)
      got, nread = Regex::Automata::Determinize.read_varu32(Slice.new(buffer.to_unsafe, buffer.size))
      got.should eq(n)
      nread.should eq(buffer.size)
    end
  end

  it "round trips representative signed varints" do
    [Int32::MIN, -1, 0, 1, 63, 64, 8192, Int32::MAX].each do |n|
      buffer = [] of UInt8
      Regex::Automata::Determinize.write_vari32(buffer, n)
      got, nread = Regex::Automata::Determinize.read_vari32(Slice.new(buffer.to_unsafe, buffer.size))
      got.should eq(n)
      nread.should eq(buffer.size)
    end
  end
end
