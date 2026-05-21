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
end
