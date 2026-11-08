require "./spec_helper"

describe "final shared source contracts" do
  it "classifies raw state IDs solely by the retained special ranges" do
    dfa = Regex::Automata::DFA::DFA.new("abc")
    (dfa.states.map(&.id) + [Regex::Automata::StateID.new(1), Regex::Automata::StateID::MAX]).each do |id|
      dfa.is_dead_state?(id).should eq(dfa.special.is_dead_state?(id))
      dfa.is_quit_state?(id).should eq(dfa.special.is_quit_state?(id))
      dfa.is_match_state?(id).should eq(dfa.special.is_match_state?(id))
      dfa.is_start_state?(id).should eq(dfa.special.is_start_state?(id))
      dfa.is_accel_state?(id).should eq(dfa.special.is_accel_state?(id))
    end
  end

  it "classifies only specialized start-state ranges as starts" do
    {false, true}.each do |specialize|
      config = Regex::Automata::DFA::Config.new.accelerate(false).specialize_start_states(specialize)
      dfa = Regex::Automata::DFA::Builder.new.configure(config).build("abc")
      id = dfa.start_state_forward(Regex::Automata::Input.new("abc")).as(Regex::Automata::StateID)
      dfa.is_start_state?(id).should eq(specialize)
    end
  end

  it "rejects match slices starting at the end of the pattern-ID payload" do
    # dense.rs::MatchStates::validate rejects start >= pattern_ids.len(),
    # including a zero-length slice. A valid empty table has no slices.
    {0_u32, 1_u32}.each do |id_count|
      words = [1_u32, id_count, 0_u32, 1_u32, id_count]
      words << 0_u32 if id_count == 1
      bytes = Bytes.new(words.size * 4)
      words.each_with_index { |word, i| IO::ByteFormat::LittleEndian.encode(word, bytes[i * 4, 4]) }
      error = expect_raises(Regex::Automata::DeserializeError) { Regex::Automata::MatchStates.from_bytes(bytes) }
      error.message.should eq("invalid pattern ID start offset")
    end
  end

  it "uses native-endian IDs for the standalone special-state payload" do
    id = Regex::Automata::StateID.new(0x01020304)
    special = Regex::Automata::Special.new(id, id, Regex::Automata::StateID::ZERO, Regex::Automata::StateID::ZERO, Regex::Automata::StateID::ZERO, Regex::Automata::StateID::ZERO, Regex::Automata::StateID::ZERO, Regex::Automata::StateID::ZERO)
    bytes = Bytes.new(32)
    special.write_to(bytes).should eq(32)
    expected = Bytes.new(32, 0_u8)
    IO::ByteFormat::SystemEndian.encode(id.as_u32, expected[0, 4])
    IO::ByteFormat::SystemEndian.encode(id.as_u32, expected[4, 4])
    bytes.should eq(expected)
    Regex::Automata::Special.from_bytes(expected).try(&.quit_id).should eq(id)
    expected.fill(255_u8)
    Regex::Automata::Special.from_bytes(expected).should be_nil
  end

  it "counts the actual optional slot payload in Crystal memory estimates" do
    info = Regex::Automata::GroupInfo.new([[nil, "named"] of String?])
    caps = Regex::Automata::Captures.all(info)
    caps.memory_usage.should eq(info.memory_usage + caps.slot_len * sizeof(Int32?))
  end

  it "preserves all valid dense transitions through the unchecked entrypoint" do
    dfa = Regex::Automata::DFA::DFA.new("[a-z]+|[0-9]{2}")
    dfa.states.each_index do |index|
      id = dfa.to_state_id(index)
      256.times do |byte|
        dfa.next_state_unchecked(id, byte.to_u8).should eq(dfa.next_state(id, byte.to_u8))
      end
    end
  end
end

private class ExtractionProbe < Regex::Automata::Captures
  getter group_reads : Int32 = 0

  def get_group(index : Int32) : Regex::Automata::Span?
    @group_reads += 1
    super
  end
end

describe "pinned lazy capture extraction" do
  it "rejects string spans that split a code point while allowing byte extraction" do
    info = Regex::Automata::GroupInfo.new([[nil] of String?])
    caps = Regex::Automata::Captures.all(info)
    caps.set_pattern(Regex::Automata::PatternID.new(0))
    caps.slots_mut[0] = 0
    caps.slots_mut[1] = 1
    expect_raises(IndexError) { caps.extract("é", 0) }
    caps.extract_bytes("é".to_slice, 0).should eq({Bytes[0xc3], [] of Bytes})
    # Rust indexes the whole match before requesting any explicit groups.
    caps.slots_mut[1] = 3
    expect_raises(IndexError) { caps.extract("é", 1) }
    expect_raises(IndexError) { caps.extract_bytes("é".to_slice, 1) }
  end

  it "stops after the requested participating groups" do
    info = Regex::Automata::GroupInfo.new([Array(String?).new(501, nil)])
    caps = ExtractionProbe.new(info, Array(Int32?).new(info.slot_len, 0))
    caps.set_pattern(Regex::Automata::PatternID.new(0))
    caps.extract("", 0).should eq({"", [] of String})
    caps.group_reads.should eq(1)
  end
end
