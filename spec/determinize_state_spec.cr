require "./spec_helper"

class Regex::Automata::Determinize::StateBuilderNFA
  def storage_capacity_for_spec : Int32
    @repr.remaining_capacity
  end
end

describe Regex::Automata::Determinize::State do
  it "round trips vendor property cases near state-ID limits and varint widths" do
    ids = [0, 127, 128, 16_383, 16_384, Regex::Automata::StateID::MAX.as_i32, 1, 255]
    builder = Regex::Automata::Determinize::StateBuilderEmpty.new.into_matches.into_nfa
    ids.each { |id| builder.add_nfa_state_id(Regex::Automata::StateID.new_unchecked(id)) }

    got = [] of Int32
    builder.to_state.iter_nfa_state_ids { |sid| got << sid.as_i32 }
    got.should eq(ids)
  end

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

  it "round trips signed deltas across non-monotonic NFA state IDs" do
    ids = [300, 3, 301, 1, 0, 2_000_000]
    builder = Regex::Automata::Determinize::StateBuilderEmpty.new
      .into_matches
      .into_nfa
    ids.each { |id| builder.add_nfa_state_id(Regex::Automata::StateID.new_unchecked(id)) }

    got = [] of Regex::Automata::StateID
    builder.to_state.iter_nfa_state_ids { |sid| got << sid }
    got.map(&.as_i32).should eq(ids)
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

  it "retains mixed pattern-ID ordering after the zero-ID optimization expands" do
    ids = [0, 5, 0, 9]
    builder = Regex::Automata::Determinize::StateBuilderEmpty.new.into_matches
    ids.each { |id| builder.add_match_pattern_id(Regex::Automata::PatternID.new_unchecked(id)) }

    state = builder.into_nfa.to_state
    state.match_pattern_ids.not_nil!.map(&.as_i32).should eq(ids)
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

  it "retains scratch capacity when a builder is cleared" do
    nfa = Regex::Automata::Determinize::StateBuilderEmpty.new
      .into_matches
      .into_nfa
    nfa.add_nfa_state_id(Regex::Automata::StateID.new_unchecked(300))

    cleared = nfa.clear
    cleared.capacity.should be >= 9
  end

  it "reports the allocated builder buffer capacity after reuse" do
    builder = Regex::Automata::Determinize::StateBuilderEmpty.new.into_matches.into_nfa
    builder.add_nfa_state_id(Regex::Automata::StateID.new_unchecked(1))
    allocated = builder.storage_capacity_for_spec

    builder.clear.capacity.should eq(allocated)
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
  it "writes the pinned zig-zag and varu32 byte representation" do
    bytes = [] of UInt8
    Regex::Automata::Determinize.write_varu32(bytes, 128_u32)
    bytes.should eq([0x80_u8, 0x01_u8])

    bytes.clear
    Regex::Automata::Determinize.write_vari32(bytes, -1)
    bytes.should eq([0x01_u8])

    bytes.clear
    Regex::Automata::Determinize.write_vari32(bytes, Int32::MIN)
    bytes.should eq([0xFF_u8, 0xFF_u8, 0xFF_u8, 0xFF_u8, 0x0F_u8])
  end

  it "round trips deterministic samples across vendor unsigned and signed varints" do
    values = [0_u32, 1_u32, 127_u32, 128_u32, 16_383_u32, 16_384_u32, UInt32::MAX]
    seed = 0_u64
    256.times do
      seed = (seed * 1_664_525_u64 + 1_013_904_223_u64) & 0xFFFF_FFFF_u64
      values << seed.to_u32
    end
    values.each do |value|
      bytes = [] of UInt8
      Regex::Automata::Determinize.write_varu32(bytes, value)
      Regex::Automata::Determinize.read_varu32(Slice.new(bytes.to_unsafe, bytes.size)).should eq({value, bytes.size})

      signed = value.unsafe_as(Int32)
      bytes.clear
      Regex::Automata::Determinize.write_vari32(bytes, signed)
      Regex::Automata::Determinize.read_vari32(Slice.new(bytes.to_unsafe, bytes.size)).should eq({signed, bytes.size})
    end
  end

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
