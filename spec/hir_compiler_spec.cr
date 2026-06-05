require "./spec_helper"
require "regex-syntax"
require "../../regex-automata/src/regex/automata/dfa"

describe Regex::Automata::HirCompiler do
  it "compiles literal" do
    hir = Regex::Syntax.parse("hello")
    compiler = Regex::Automata::HirCompiler.new
    nfa = compiler.compile(hir)
    nfa.should be_a(Regex::Automata::NFA::NFA)
    nfa.size.should be > 0
  end

  it "compiles alternation" do
    hir = Regex::Syntax.parse("a|b")
    compiler = Regex::Automata::HirCompiler.new
    nfa = compiler.compile(hir)
    nfa.should be_a(Regex::Automata::NFA::NFA)
    nfa.size.should be > 0
  end

  it "compiles character class" do
    hir = Regex::Syntax.parse("[a-z]")
    compiler = Regex::Automata::HirCompiler.new
    nfa = compiler.compile(hir)
    nfa.should be_a(Regex::Automata::NFA::NFA)
    nfa.size.should be > 0
  end

  it "compiles repetition" do
    hir = Regex::Syntax.parse("a*")
    compiler = Regex::Automata::HirCompiler.new
    nfa = compiler.compile(hir)
    nfa.should be_a(Regex::Automata::NFA::NFA)
    nfa.size.should be > 0
  end

  it "compiles general repetition ranges" do
    # Test various repetition ranges
    patterns = {
      "a{2}"   => {min: 2, max: 2},
      "a{2,5}" => {min: 2, max: 5},
      "a{2,}"  => {min: 2, max: nil},
      "a{0,3}" => {min: 0, max: 3},
    }

    patterns.each do |pattern, expected|
      hir = Regex::Syntax.parse(pattern)
      compiler = Regex::Automata::HirCompiler.new
      nfa = compiler.compile(hir)
      nfa.should be_a(Regex::Automata::NFA::NFA)
      nfa.size.should be > 0

      # Basic smoke test: compile DFA and match
      dfa_builder = Regex::Automata::DFA::Builder.from_nfa(nfa)
      dfa = dfa_builder.build

      min = expected[:min]
      max = expected[:max]

      # Test matching exact min copies
      match = dfa.find_longest_match("a" * min)
      match.should_not be_nil
      end_pos, pattern_ids = match.not_nil!
      end_pos.should eq(min)
      pattern_ids.should eq([Regex::Automata::PatternID.new(0)])

      # Test matching within range
      if max
        test_count = (min + 1).clamp(min, max)
        match = dfa.find_longest_match("a" * test_count)
        match.should_not be_nil
        end_pos, pattern_ids = match.not_nil!
        end_pos.should eq(test_count)
      end

      # Test matching beyond max (should stop at max)
      if max
        beyond = max + 2
        match = dfa.find_longest_match("a" * beyond)
        match.should_not be_nil
        end_pos, pattern_ids = match.not_nil!
        end_pos.should eq(max)
      end

      # Test matching less than min (should not match)
      if min > 0
        less = min - 1
        match = dfa.find_longest_match("a" * less)
        match.should be_nil
      end
    end
  end

  it "compiles grouped repetition ranges" do
    cases = {
      "(ab){2}"   => {"ab" => nil, "abab" => 4, "ababab" => 4},
      "(ab){2,3}" => {"ab" => nil, "abab" => 4, "ababab" => 6, "abababab" => 6},
      "(ab){2,}"  => {"ab" => nil, "abab" => 4, "ababab" => 6, "abababab" => 8},
    }

    cases.each do |pattern, inputs|
      hir = Regex::Syntax.parse(pattern)
      nfa = Regex::Automata::HirCompiler.new.compile(hir)
      dfa = Regex::Automata::DFA::Builder.from_nfa(nfa).build

      inputs.each do |input, expected_end|
        match = dfa.find_longest_match(input)
        if expected_end.nil?
          match.should be_nil
        else
          match.should_not be_nil
          end_pos, pattern_ids = match.not_nil!
          end_pos.should eq(expected_end)
          pattern_ids.should eq([Regex::Automata::PatternID.new(0)])
        end
      end
    end
  end

  it "compiles concatenation" do
    hir = Regex::Syntax.parse("ab")
    compiler = Regex::Automata::HirCompiler.new
    nfa = compiler.compile(hir)
    nfa.should be_a(Regex::Automata::NFA::NFA)
    nfa.size.should be > 0
  end

  it "compiles dot" do
    hir = Regex::Syntax.parse(".")
    compiler = Regex::Automata::HirCompiler.new
    nfa = compiler.compile(hir)
    nfa.should be_a(Regex::Automata::NFA::NFA)
    nfa.size.should be > 0
  end

  it "compiles escape sequences" do
    hir = Regex::Syntax.parse("\\n")
    compiler = Regex::Automata::HirCompiler.new
    nfa = compiler.compile(hir)
    nfa.should be_a(Regex::Automata::NFA::NFA)
    nfa.size.should be > 0
  end

  it "compiles multiple patterns with unique IDs" do
    hirs = ["a", "b", "c"].map { |pat| Regex::Syntax.parse(pat) }
    compiler = Regex::Automata::HirCompiler.new
    nfa = compiler.compile_multi(hirs)
    nfa.should be_a(Regex::Automata::NFA::NFA)
    nfa.size.should be > 0
    nfa.start_pattern.size.should eq(3)
  end

  it "matches correct pattern IDs with DFA" do
    hirs = ["a", "b", "c"].map { |pat| Regex::Syntax.parse(pat) }
    compiler = Regex::Automata::HirCompiler.new
    nfa = compiler.compile_multi(hirs)

    dfa_builder = Regex::Automata::DFA::Builder.from_nfa(nfa)
    dfa = dfa_builder.build

    # Test each pattern
    match = dfa.find_longest_match("a")
    match.should_not be_nil
    end_pos, pattern_ids = match.not_nil!
    end_pos.should eq(1)
    pattern_ids.should eq([Regex::Automata::PatternID.new(0)])

    match = dfa.find_longest_match("b")
    match.should_not be_nil
    end_pos, pattern_ids = match.not_nil!
    pattern_ids.should eq([Regex::Automata::PatternID.new(1)])

    match = dfa.find_longest_match("c")
    match.should_not be_nil
    end_pos, pattern_ids = match.not_nil!
    pattern_ids.should eq([Regex::Automata::PatternID.new(2)])

    match = dfa.find_longest_match("d")
    match.should be_nil
  end

  it "compiles look-around assertions" do
    # Test that look-around assertions compile to NFA
    patterns = ["^a", "a$", "(?-u:\\b)a", "a(?-u:\\b)", "\\Aa", "a\\z", "a\\Z"]

    patterns.each do |pattern|
      hir = Regex::Syntax.parse(pattern)
      compiler = Regex::Automata::HirCompiler.new
      nfa = compiler.compile(hir)
      nfa.should be_a(Regex::Automata::NFA::NFA)
      nfa.size.should be > 0

      # Basic smoke test: compile DFA (even if matching won't work correctly yet)
      dfa_builder = Regex::Automata::DFA::Builder.from_nfa(nfa)
      dfa = dfa_builder.build
      dfa.should be_a(Regex::Automata::DFA::DFA)
    end
  end

  it "compiles capture groups into capture states" do
    hir = Regex::Syntax.parse("(ab)")
    nfa = Regex::Automata::HirCompiler.new.compile(hir)

    capture_states = nfa.states.select(&.is_a?(Regex::Automata::NFA::Capture)).map(&.as(Regex::Automata::NFA::Capture))
    capture_states.size.should eq(2)

    # Parser capture indices are 1-based.
    capture_states.all? { |state| state.group_index == 1 }.should be_true
    capture_states.map(&.slot).sort.should eq([2, 3])
  end
end
