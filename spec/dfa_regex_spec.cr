require "./spec_helper"

describe "DFA::Regex" do
  it "creates a regex with Regex::new" do
    re = Regex::Automata::DFA::Regex.new("foo[0-9]+bar")
    re.should_not be_nil
    re.is_match("foo12345bar").should be_true
    re.is_match("foobar").should be_false
  end

  it "creates a regex with Regex::new_many for multiple patterns" do
    re = Regex::Automata::DFA::Regex.new_many(["[a-z]+", "[0-9]+"])
    re.should_not be_nil

    matches = re.find_iter("abc 1 foo 4567 0 quux").to_a
    matches.should eq([
      Regex::Automata::Match.must(0, 0...3),
      Regex::Automata::Match.must(1, 4...5),
      Regex::Automata::Match.must(0, 6...9),
      Regex::Automata::Match.must(1, 10...14),
      Regex::Automata::Match.must(1, 15...16),
      Regex::Automata::Match.must(0, 17...21),
    ])
  end

  it "creates a regex with Regex::builder" do
    re = Regex::Automata::DFA::Regex.builder.build("foo[0-9]+bar")
    re.should_not be_nil
    re.is_match("foo12345bar").should be_true
  end

  it "finds matches with Regex#find" do
    re = Regex::Automata::DFA::Regex.new("foo[0-9]+")

    # Greediness is applied appropriately
    match = re.find("zzzfoo12345zzz")
    match.should_not be_nil
    if match
      match.pattern.should eq(Regex::Automata::PatternID.new(0))
      match.start.should eq(3)
      match.end.should eq(11) # "foo12345" is 8 chars starting at position 3
    end

    # No match case
    re.find("zzzbarzzz").should be_nil
  end

  it "applies leftmost-first match semantics" do
    re = Regex::Automata::DFA::Regex.new("abc|a")

    # Even though 'a' matches at position 0, leftmost-first prefers 'abc'
    match = re.find("abc")
    match.should_not be_nil
    if match
      match.pattern.should eq(Regex::Automata::PatternID.new(0))
      match.start.should eq(0)
      match.end.should eq(3) # "abc"
    end
  end

  it "iterates over matches with Regex#find_iter" do
    re = Regex::Automata::DFA::Regex.new("foo[0-9]+")
    text = "foo1 foo12 foo123"

    matches = [] of Regex::Automata::Match
    re.find_iter(text).each do |match|
      matches << match
    end

    matches.size.should eq(3)

    # Check first match
    matches[0].pattern.should eq(Regex::Automata::PatternID.new(0))
    matches[0].start.should eq(0)
    matches[0].end.should eq(4) # "foo1"

    # Check second match
    matches[1].pattern.should eq(Regex::Automata::PatternID.new(0))
    matches[1].start.should eq(5)
    matches[1].end.should eq(10) # "foo12"

    # Check third match
    matches[2].pattern.should eq(Regex::Automata::PatternID.new(0))
    matches[2].start.should eq(11)
    matches[2].end.should eq(17) # "foo123"
  end

  it "handles pattern_len for multi-pattern regexes" do
    re = Regex::Automata::DFA::Regex.new_many(["[a-z]+", "[0-9]+", "[A-Z]+"])
    re.pattern_len.should eq(3)

    re2 = Regex::Automata::DFA::Regex.new("single")
    re2.pattern_len.should eq(1)
  end

  it "supports builder configuration" do
    # Test builder with configuration
    re = Regex::Automata::DFA::Regex.builder
      .configure { |config| config.quit('x'.ord.to_u8, true) }
      .build("foo[0-9]+")

    re.should_not be_nil

    # This should work normally
    re.is_match("foo123").should be_true

    # With quit byte 'x', searching "foox123" might fail
    # We'll need to implement try_search to test this properly
  end

  it "supports dense builder aliases" do
    re = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.quit('x'.ord.to_u8, true))
      .build("abcd")

    result = re.try_search(Regex::Automata::Input.new("abcx"))
    result.should be_a(Regex::Automata::MatchError)
    result.as(Regex::Automata::MatchError).quit?.should be_true
  end

  it "supports syntax builder aliases" do
    re = Regex::Automata::DFA::Regex.builder
      .syntax { |config| config.unicode(false).utf8(false) }
      .thompson { |config| config.utf8(false) }
      .build("(?-u:[\\xFF])")

    re.find(Bytes[0xFF_u8]).should eq(Regex::Automata::Match.must(0, 0...1))
  end

  it "supports sparse regex convenience constructors" do
    re = Regex::Automata::DFA::Regex.new_sparse("foo[0-9]+")
    re.find("foo123").should eq(Regex::Automata::Match.must(0, 0...6))

    many = Regex::Automata::DFA::Regex.new_many_sparse(["[a-z]+", "[0-9]+"])
    many.find("123").should eq(Regex::Automata::Match.must(1, 0...3))
  end

  it "supports sparse regex builders" do
    re = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.start_kind(Regex::Automata::StartKind::Anchored))
      .build_sparse("foo[0-9]+")

    re.try_search(Regex::Automata::Input.new("foo123").anchored(Regex::Automata::Anchored::Yes)).should eq(
      Regex::Automata::Match.must(0, 0...6)
    )
  end

  it "handles empty patterns" do
    re = Regex::Automata::DFA::Regex.new("")
    re.should_not be_nil

    # Empty pattern matches empty string
    re.is_match("").should be_true

    # Empty pattern also matches at boundaries of non-empty strings
    # This depends on DFA implementation
  end

  it "supports building from existing DFAs" do
    # First build a regex normally
    initial_re = Regex::Automata::DFA::Regex.new("foo[0-9]+")
    initial_re.is_match("foo123").should be_true

    # Get the forward and reverse DFAs
    forward = initial_re.forward
    reverse = initial_re.reverse

    # Build a new regex from the DFAs
    re = Regex::Automata::DFA::Regex.builder.build_from_dfas(forward, reverse)
    re.should_not be_nil
    re.is_match("foo123").should be_true
  end

  it "uses full haystack context for ranged searches" do
    re = Regex::Automata::DFA::Regex.new("(?-u:\\b).+(?-u:\\b)")

    re.find("foo".to_slice[1...2]).should eq(Regex::Automata::Match.must(0, 0...1))
    re.try_search(Regex::Automata::Input.new("foo").range(1...2)).should be_nil
  end

  it "uses reverse search to recover match starts for ranged searches" do
    re = Regex::Automata::DFA::Regex.new("foo[0-9]+")

    re.try_search(Regex::Automata::Input.new("zzfoo123xx").range(0...8)).should eq(
      Regex::Automata::Match.must(0, 2...8)
    )
  end

  it "iterates empty matches without splitting UTF-8 codepoints" do
    re = Regex::Automata::DFA::Regex.new("")

    re.find_iter("abc").to_a.should eq([
      Regex::Automata::Match.must(0, 0...0),
      Regex::Automata::Match.must(0, 1...1),
      Regex::Automata::Match.must(0, 2...2),
      Regex::Automata::Match.must(0, 3...3),
    ])

    re.find_iter("☃").to_a.should eq([
      Regex::Automata::Match.must(0, 0...0),
      Regex::Automata::Match.must(0, 3...3),
    ])
  end

  describe "error handling" do
    it "returns BuildError for invalid patterns" do
      expect_raises(Regex::Automata::BuildError) do
        Regex::Automata::DFA::Regex.new("invalid[")
      end
    end

    it "panics on search errors by default" do
      # Create a regex with quit bytes
      re = Regex::Automata::DFA::Regex.builder
        .configure { |config| config.quit('x'.ord.to_u8, true) }
        .build("abcd") # Pattern that would need to see 'x'

      # Searching "abcx" should panic because 'x' is a quit byte
      expect_raises(Exception) do
        re.is_match("abcx")
      end
    end

    it "provides try_search for error handling" do
      re = Regex::Automata::DFA::Regex.builder
        .configure { |config| config.quit('x'.ord.to_u8, true) }
        .build("abcd")

      # try_search should return an error instead of panicking
      result = re.try_search(Regex::Automata::Input.new("abcx"))
      result.should be_a(Regex::Automata::MatchError)

      error = result.as(Regex::Automata::MatchError)
      error.quit?.should be_true
      error.byte.should eq('x'.ord.to_u8)
      error.offset.should eq(3)
    end
  end
end
