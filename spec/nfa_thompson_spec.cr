require "./spec_helper"

private def pid(id : Int32) : Regex::Automata::PatternID
  Regex::Automata::PatternID.new(id)
end

private def sid(id : Int32) : Regex::Automata::StateID
  Regex::Automata::StateID.new(id)
end

private def s_byte(byte : UInt8, next_id : Int32) : Regex::Automata::NFA::ByteRange
  Regex::Automata::NFA::ByteRange.new(
    Regex::Automata::NFA::Transition.new(byte, byte, sid(next_id))
  )
end

private def s_range(start_byte : UInt8, end_byte : UInt8, next_id : Int32) : Regex::Automata::NFA::ByteRange
  Regex::Automata::NFA::ByteRange.new(
    Regex::Automata::NFA::Transition.new(start_byte, end_byte, sid(next_id))
  )
end

private def s_look(kind : Regex::Automata::NFA::Look::Kind, next_id : Int32) : Regex::Automata::NFA::Look
  Regex::Automata::NFA::Look.new(kind, sid(next_id))
end

private def s_match(pattern_id : Int32, next_id : Int32? = nil) : Regex::Automata::NFA::Match
  Regex::Automata::NFA::Match.new(pid(pattern_id), next_id.try { |id| sid(id) })
end

private def s_cap(next_id : Int32, pattern_id : Int32, group_index : Int32, slot : Int32) : Regex::Automata::NFA::Capture
  Regex::Automata::NFA::Capture.new(sid(next_id), pid(pattern_id), group_index, slot)
end

private def s_bin_union(left : Int32, right : Int32) : Regex::Automata::NFA::BinaryUnion
  Regex::Automata::NFA::BinaryUnion.new(sid(left), sid(right))
end

private def s_union(ids : Array(Int32)) : Regex::Automata::NFA::Union
  Regex::Automata::NFA::Union.new(ids.map { |id| sid(id) })
end

private def s_fail : Regex::Automata::NFA::Fail
  Regex::Automata::NFA::Fail.new
end

describe Regex::Automata::NFA::NFA do
  it "exposes Thompson compiler config and public constructors" do
    lookm = Regex::Automata::LookMatcher.new
    lookm.set_line_terminator(0_u8)

    config = Regex::Automata::NFA::NFA.config
      .utf8(false)
      .reverse(true)
      .nfa_size_limit(123_i64)
      .shrink(true)
      .which_captures(Regex::Automata::NFA::WhichCaptures::Implicit)
      .look_matcher(lookm)

    config.get_utf8.should be_false
    config.get_reverse.should be_true
    config.get_nfa_size_limit.should eq(123_i64)
    config.get_shrink.should be_true
    config.get_which_captures.should eq(Regex::Automata::NFA::WhichCaptures::Implicit)
    config.get_look_matcher.get_line_terminator.should eq(0_u8)

    compiler = Regex::Automata::NFA::NFA.compiler
    compiler.configure(config).should be(compiler)
    compiler.syntax(Regex::Automata::Syntax::Config.new.utf8(false)).should be(compiler)

    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .utf8(false)
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .syntax(Regex::Automata::Syntax::Config.new.utf8(false))
      .build("(?-u)\\xFF")
    nfa.is_utf8.should be_false
    nfa.pattern_len.should eq(1)
  end

  it "reports NFA size-limit failures through BuildError introspection" do
    error = expect_raises(Regex::Automata::BuildError) do
      Regex::Automata::NFA::NFA.compiler
        .configure(Regex::Automata::NFA::NFA.config.nfa_size_limit(0_i64))
        .build("abc")
    end

    error.is_size_limit_exceeded.should be_true
    error.size_limit.should eq(0_i64)
  end

  it "builds always-match and never-match NFAs" do
    always = Regex::Automata::NFA::NFA.always_match
    always.pattern_len.should eq(1)
    always.has_capture.should be_true
    always.has_empty.should be_true
    always.start_pattern(pid(0)).should eq(always.start_anchored)
    always.state(always.start_anchored).should eq(s_cap(1, 0, 0, 0))
    always.states.should eq([
      s_cap(1, 0, 0, 0),
      s_cap(2, 0, 0, 1),
      s_match(0),
    ])

    never = Regex::Automata::NFA::NFA.never_match
    never.pattern_len.should eq(0)
    never.has_capture.should be_false
    never.has_empty.should be_false
    never.start_pattern(pid(0)).should be_nil
    never.states.should eq([s_fail])
  end

  it "matches always-match and never-match NFAs through PikeVM over ranged input" do
    always = Regex::Automata::NFA::PikeVM.new_from_nfa(Regex::Automata::NFA::NFA.always_match)
    always_cache = always.create_cache
    always_caps = always.create_captures
    always_find = ->(haystack : String, start : Int32, finish : Int32) do
      input = Regex::Automata::Input.new(haystack).range(start...finish)
      always.search(always_cache, input, always_caps)
      always_caps.get_match.try(&.end)
    end

    always_find.call("", 0, 0).should eq(0)
    always_find.call("a", 0, 1).should eq(0)
    always_find.call("a", 1, 1).should eq(1)
    always_find.call("ab", 0, 2).should eq(0)
    always_find.call("ab", 1, 2).should eq(1)
    always_find.call("ab", 2, 2).should eq(2)

    never = Regex::Automata::NFA::PikeVM.new_from_nfa(Regex::Automata::NFA::NFA.never_match)
    never_cache = never.create_cache
    never_caps = never.create_captures
    never_find = ->(haystack : String, start : Int32, finish : Int32) do
      input = Regex::Automata::Input.new(haystack).range(start...finish)
      never.search(never_cache, input, never_caps)
      never_caps.get_match.try(&.end)
    end

    never_find.call("", 0, 0).should be_nil
    never_find.call("a", 0, 1).should be_nil
    never_find.call("a", 1, 1).should be_nil
    never_find.call("ab", 0, 2).should be_nil
    never_find.call("ab", 1, 2).should be_nil
    never_find.call("ab", 2, 2).should be_nil
  end

  it "adds the unanchored prefix when compiling unanchored patterns" do
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .build("a")

    nfa.states.should eq([
      s_bin_union(2, 1),
      s_range(0_u8, 255_u8, 0),
      s_byte('a'.ord.to_u8, 3),
      s_match(0),
    ])
    nfa.start_anchored.should eq(sid(2))
    nfa.start_unanchored.should eq(sid(0))
    nfa.start_pattern(pid(0)).should eq(sid(2))
    nfa.is_always_start_anchored.should be_false
  end

  it "omits the unanchored prefix for start-anchored patterns" do
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .build("^a")

    nfa.start_anchored.should eq(nfa.start_unanchored)
    nfa.is_always_start_anchored.should be_true
    nfa.state(nfa.start_anchored).should be_a(Regex::Automata::NFA::Look)
    nfa.look_set_any.contains_anchor.should be_true
    nfa.look_set_prefix_any.contains_anchor.should be_true
    nfa.look_set_prefix_all.contains_anchor.should be_true
  end

  it "keeps the unanchored prefix for end-anchored patterns" do
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .build("a$")

    nfa.state(nfa.start_unanchored).should eq(s_bin_union(2, 1))
    nfa.look_set_any.contains_anchor.should be_true
    nfa.look_set_prefix_any.should be_empty
    nfa.look_set_prefix_all.should be_empty
  end

  it "tracks per-pattern starts for multi-pattern compilation" do
    nfa = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
          .unanchored_prefix(false)
      )
      .build_many(["a", "b"])

    nfa.states.should eq([
      s_byte('a'.ord.to_u8, 1),
      s_match(0),
      s_byte('b'.ord.to_u8, 3),
      s_match(1),
      s_bin_union(0, 2),
    ])
    nfa.pattern_len.should eq(2)
    nfa.patterns.to_a.should eq([pid(0), pid(1)])
    nfa.start_anchored.should eq(sid(4))
    nfa.start_unanchored.should eq(sid(4))
    nfa.start_pattern(pid(0)).should eq(sid(0))
    nfa.start_pattern(pid(1)).should eq(sid(2))
    nfa.start_pattern(pid(2)).should be_nil
  end

  it "supports all implicit and no capture policies" do
    all = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .unanchored_prefix(false)
          .which_captures(Regex::Automata::NFA::WhichCaptures::All)
      )
      .build("a(b)c")
    all.has_capture.should be_true
    all.group_info.all_group_len.should eq(2)
    all.states.select(&.is_a?(Regex::Automata::NFA::Capture)).map(&.as(Regex::Automata::NFA::Capture).slot).sort.should eq([0, 1, 2, 3])

    implicit = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .unanchored_prefix(false)
          .which_captures(Regex::Automata::NFA::WhichCaptures::Implicit)
      )
      .build("a(b)c")
    implicit.group_info.all_group_len.should eq(1)
    implicit.states.select(&.is_a?(Regex::Automata::NFA::Capture)).map(&.as(Regex::Automata::NFA::Capture).slot).sort.should eq([0, 1])

    none = Regex::Automata::NFA::NFA.compiler
      .configure(
        Regex::Automata::NFA::NFA.config
          .unanchored_prefix(false)
          .which_captures(Regex::Automata::NFA::WhichCaptures::None)
      )
      .build("a(b)c")
    none.has_capture.should be_false
    none.group_info.all_group_len.should eq(0)
  end
end
