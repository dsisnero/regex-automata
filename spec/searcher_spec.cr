require "./spec_helper"

describe Regex::Automata::Searcher do
  it "advances half matches like vendor util::iter examples" do
    re = Regex::Automata::DFA::Regex.new("[0-9]{4}-[0-9]{2}-[0-9]{2}")
    input = Regex::Automata::Input.new("2010-03-14 2016-10-08 2020-10-22")
    it = Regex::Automata::Searcher.new(input)

    it.advance_half { |search| re.forward.try_search_fwd(search) }.should eq(
      Regex::Automata::HalfMatch.must(0, 10)
    )
    it.advance_half { |search| re.forward.try_search_fwd(search) }.should eq(
      Regex::Automata::HalfMatch.must(0, 21)
    )
    it.advance_half { |search| re.forward.try_search_fwd(search) }.should eq(
      Regex::Automata::HalfMatch.must(0, 32)
    )
    it.advance_half { |search| re.forward.try_search_fwd(search) }.should be_nil
  end

  it "advances empty half matches without overlapping the previous end" do
    input = Regex::Automata::Input.new("abba")
    it = Regex::Automata::Searcher.new(input)
    finder = ->(search : Regex::Automata::Input) do
      case search.start
      when 0
        Regex::Automata::HalfMatch.must(0, 1)
      when 1
        Regex::Automata::HalfMatch.must(0, 1)
      when 2
        Regex::Automata::HalfMatch.must(0, 2)
      when 3
        Regex::Automata::HalfMatch.must(0, 4)
      else
        nil
      end
    end

    it.advance_half { |search| finder.call(search) }.should eq(
      Regex::Automata::HalfMatch.must(0, 1)
    )
    it.advance_half { |search| finder.call(search) }.should eq(
      Regex::Automata::HalfMatch.must(0, 2)
    )
    it.advance_half { |search| finder.call(search) }.should eq(
      Regex::Automata::HalfMatch.must(0, 4)
    )
    it.advance_half { |search| finder.call(search) }.should be_nil
  end

  it "exposes the current input and iterator constructors" do
    re = Regex::Automata::DFA::Regex.new("[0-9]{4}-[0-9]{2}-[0-9]{2}")
    input = Regex::Automata::Input.new("2010-03-14 2016-10-08 2020-10-22")
    searcher = Regex::Automata::Searcher.new(input)

    searcher.input.start.should eq(0)
    searcher.advance { |search| re.try_search(search) }.should eq(
      Regex::Automata::Match.must(0, 0...10)
    )
    searcher.input.start.should eq(10)

    matches = Regex::Automata::Searcher.new(input)
      .into_matches_iter { |search| re.try_search(search) }
      .infallible
      .to_a

    matches.should eq([
      Regex::Automata::Match.must(0, 0...10),
      Regex::Automata::Match.must(0, 11...21),
      Regex::Automata::Match.must(0, 22...32),
    ])
  end

  it "iterates captures snapshots without reusing yielded objects" do
    info = Regex::Automata::GroupInfo.new([
      [nil, "year"] of String?,
    ])
    caps = Regex::Automata::Captures.all(info)
    input = Regex::Automata::Input.new("2010-03 2016-10 2020-11")

    it = Regex::Automata::Searcher.new(input).into_captures_iter(caps) do |search, current|
      current.clear
      current.set_pattern(Regex::Automata::PatternID.new(0))

      case search.start
      when 0
        slots = current.slots_mut
        slots[0] = 0; slots[1] = 7
        slots[2] = 0; slots[3] = 4
      when 7
        slots = current.slots_mut
        slots[0] = 8; slots[1] = 15
        slots[2] = 8; slots[3] = 12
      when 15
        slots = current.slots_mut
        slots[0] = 16; slots[1] = 23
        slots[2] = 16; slots[3] = 20
      else
        current.clear
      end
      nil
    end.infallible

    first = it.next.not_nil!
    second = it.next.not_nil!
    third = it.next.not_nil!

    first.get_match.should eq(Regex::Automata::Match.must(0, 0...7))
    first.get_group_by_name("year").should eq(Regex::Automata::Span.new(0, 4))
    second.get_match.should eq(Regex::Automata::Match.must(0, 8...15))
    second.get_group_by_name("year").should eq(Regex::Automata::Span.new(8, 12))
    third.get_match.should eq(Regex::Automata::Match.must(0, 16...23))
    third.get_group_by_name("year").should eq(Regex::Automata::Span.new(16, 20))

    # Earlier yielded captures must remain stable after later searches.
    first.get_group_by_name("year").should eq(Regex::Automata::Span.new(0, 4))
    second.get_group_by_name("year").should eq(Regex::Automata::Span.new(8, 12))
    it.next.should be_nil
  end

  it "advances empty captures matches without overlapping the previous end" do
    info = Regex::Automata::GroupInfo.new([
      [nil] of String?,
    ])
    caps = Regex::Automata::Captures.all(info)
    input = Regex::Automata::Input.new("abba")

    it = Regex::Automata::Searcher.new(input).into_captures_iter(caps) do |search, current|
      current.clear
      case search.start
      when 0
        current.set_pattern(Regex::Automata::PatternID.new(0))
        slots = current.slots_mut
        slots[0] = 0; slots[1] = 1
      when 1
        current.set_pattern(Regex::Automata::PatternID.new(0))
        slots = current.slots_mut
        slots[0] = 1; slots[1] = 1
      when 2
        current.set_pattern(Regex::Automata::PatternID.new(0))
        slots = current.slots_mut
        slots[0] = 2; slots[1] = 2
      when 3
        current.set_pattern(Regex::Automata::PatternID.new(0))
        slots = current.slots_mut
        slots[0] = 3; slots[1] = 4
      end
      nil
    end.infallible

    it.next.not_nil!.get_match.should eq(Regex::Automata::Match.must(0, 0...1))
    it.next.not_nil!.get_match.should eq(Regex::Automata::Match.must(0, 2...2))
    it.next.not_nil!.get_match.should eq(Regex::Automata::Match.must(0, 3...4))
    it.next.should be_nil
  end
end
