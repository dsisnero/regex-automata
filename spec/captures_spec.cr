require "./spec_helper"
require "regex-syntax"

describe Regex::Automata::GroupInfo do
  it "tracks slot and name mappings across patterns" do
    info = Regex::Automata::GroupInfo.new([
      [nil, "foo", "bar"] of String?,
      [nil, nil, "foo"] of String?,
    ])

    pid0 = Regex::Automata::PatternID.new(0)
    pid1 = Regex::Automata::PatternID.new(1)

    info.pattern_len.should eq(2)
    info.group_len(pid0).should eq(3)
    info.group_len(pid1).should eq(3)
    info.all_group_len.should eq(6)
    info.slot_len.should eq(12)
    info.implicit_slot_len.should eq(4)
    info.explicit_slot_len.should eq(8)

    info.to_index(pid0, "foo").should eq(1)
    info.to_index(pid1, "foo").should eq(2)
    info.to_index(pid1, "bar").should be_nil
    info.to_name(pid0, 0).should be_nil
    info.to_name(pid0, 2).should eq("bar")
    info.to_name(pid1, 2).should eq("foo")

    info.slots(pid0, 0).should eq({0, 1})
    info.slots(pid1, 0).should eq({2, 3})
    info.slots(pid0, 1).should eq({4, 5})
    info.slots(pid0, 2).should eq({6, 7})
    info.slots(pid1, 1).should eq({8, 9})
    info.slots(pid1, 2).should eq({10, 11})

    info.pattern_names(pid0).to_a.should eq([nil, "foo", "bar"])
    info.pattern_names(pid1).to_a.should eq([nil, nil, "foo"])
    info.all_names.to_a.should eq([
      {pid0, 0, nil},
      {pid0, 1, "foo"},
      {pid0, 2, "bar"},
      {pid1, 0, nil},
      {pid1, 1, nil},
      {pid1, 2, "foo"},
    ])
  end

  it "validates group invariants" do
    expect_raises(Regex::Automata::GroupInfoError, /no capturing groups found for pattern 0/) do
      Regex::Automata::GroupInfo.new([
        [] of String?,
      ])
    end

    expect_raises(Regex::Automata::GroupInfoError, /first capture group .* must be unnamed/) do
      Regex::Automata::GroupInfo.new([
        ["foo"] of String?,
      ])
    end

    expect_raises(Regex::Automata::GroupInfoError, /duplicate capture group name 'foo'/) do
      Regex::Automata::GroupInfo.new([
        [nil, "foo", "foo"] of String?,
      ])
    end
  end
end

describe Regex::Automata::Captures do
  it "supports full match, group, and name lookups" do
    info = Regex::Automata::GroupInfo.new([
      [nil, "lhs", nil] of String?,
      [nil, nil, "rhs"] of String?,
    ])
    pid1 = Regex::Automata::PatternID.new(1)

    caps = Regex::Automata::Captures.all(info)
    caps.set_pattern(pid1)
    slots = caps.slots_mut
    slots[2] = 0
    slots[3] = 6
    slots[8] = 0
    slots[9] = 3
    slots[10] = 3
    slots[11] = 6

    caps.is_match.should be_true
    caps.pattern.should eq(pid1)
    caps.get_match.should eq(Regex::Automata::Match.must(1, 0, 6))
    caps.get_group(0).should eq(Regex::Automata::Span.new(0, 6))
    caps.get_group(1).should eq(Regex::Automata::Span.new(0, 3))
    caps.get_group(2).should eq(Regex::Automata::Span.new(3, 6))
    caps.get_group_by_name("rhs").should eq(Regex::Automata::Span.new(3, 6))
    caps.iter.to_a.should eq([
      Regex::Automata::Span.new(0, 6),
      Regex::Automata::Span.new(0, 3),
      Regex::Automata::Span.new(3, 6),
    ])

    caps.clear
    caps.is_match.should be_false
    caps.get_match.should be_nil
    caps.slots.compact.should be_empty
  end

  it "preserves the lighter-weight constructor behavior" do
    info = Regex::Automata::GroupInfo.new([
      [nil, "name"] of String?,
      [nil] of String?,
    ])

    matches = Regex::Automata::Captures.matches(info)
    matches.slot_len.should eq(4)
    matches.set_pattern(Regex::Automata::PatternID.new(0))
    matches.slots_mut[0] = 1
    matches.slots_mut[1] = 4
    matches.get_match.should eq(Regex::Automata::Match.must(0, 1, 4))
    matches.get_group(1).should be_nil
    matches.get_group_by_name("name").should be_nil

    empty = Regex::Automata::Captures.empty(info)
    empty.set_pattern(Regex::Automata::PatternID.new(1))
    empty.is_match.should be_true
    empty.get_match.should be_nil
  end

  it "interpolates string and byte replacements" do
    info = Regex::Automata::GroupInfo.new([
      [nil, "day", "month", "year"] of String?,
    ])
    caps = Regex::Automata::Captures.all(info)
    caps.set_pattern(Regex::Automata::PatternID.new(0))

    slots = caps.slots_mut
    slots[0] = 3
    slots[1] = 13
    slots[2] = 3
    slots[3] = 5
    slots[4] = 6
    slots[5] = 8
    slots[6] = 9
    slots[7] = 13

    haystack = "On 14-03-2010."
    replacement = "year=$year month=${month} day=$1"
    caps.interpolate_string(haystack, replacement).should eq("year=2010 month=03 day=14")

    interpolated = caps.interpolate_bytes(haystack.to_slice, "day=$day".to_slice)
    String.new(interpolated).should eq("day=14")
  end
end

describe Regex::Automata::HirCompiler do
  it "assigns compiled capture slots from group info for each pattern" do
    nfa = Regex::Automata::HirCompiler.new.compile_multi([
      Regex::Syntax.parse("(?P<lhs>a)(b)"),
      Regex::Syntax.parse("(x)(?P<rhs>y)"),
    ])

    pid0 = Regex::Automata::PatternID.new(0)
    pid1 = Regex::Automata::PatternID.new(1)

    nfa.group_info.pattern_names(pid0).to_a.should eq([nil, "lhs", nil])
    nfa.group_info.pattern_names(pid1).to_a.should eq([nil, nil, "rhs"])

    capture_states = nfa.states.select(&.is_a?(Regex::Automata::NFA::Capture)).map(&.as(Regex::Automata::NFA::Capture))
    pid0_group1_slots = capture_states.select { |state| state.pattern_id == pid0 && state.group_index == 1 }.map(&.slot).sort
    pid1_group1_slots = capture_states.select { |state| state.pattern_id == pid1 && state.group_index == 1 }.map(&.slot).sort
    pid1_group2_slots = capture_states.select { |state| state.pattern_id == pid1 && state.group_index == 2 }.map(&.slot).sort

    pid0_group1_slots.should eq([4, 5])
    pid1_group1_slots.should eq([8, 9])
    pid1_group2_slots.should eq([10, 11])
    nfa.group_info.slots(pid1, 1).should eq({8, 9})
    nfa.group_info.slots(pid1, 2).should eq({10, 11})
  end

  it "keeps the implicit whole-pattern group even without explicit captures" do
    nfa = Regex::Automata::HirCompiler.new.compile(Regex::Syntax.parse("abc"))

    nfa.group_info.pattern_len.should eq(1)
    nfa.group_info.group_len(Regex::Automata::PatternID.new(0)).should eq(1)
    nfa.group_info.pattern_names(Regex::Automata::PatternID.new(0)).to_a.should eq([nil])
  end
end
