require "./spec_helper"

# Rust's util/empty.rs checks the low-level engine result, not just match
# iterators. A bounded search may begin inside the bytes of a valid codepoint.
describe "vendor UTF-8 empty-match search contract" do
  it "propagates an error from a forward retry without changing the caller input" do
    input = Regex::Automata::Input.new("☃").range(1...3)
    starts = [] of Int32
    error = Regex::Automata::MatchError.quit(0x98_u8, 2)

    result = Regex::Automata::Empty.skip_splits_fwd(input, Regex::Automata::HalfMatch.must(0, 1)) do |retry|
      starts << retry.start
      error
    end

    result.should eq(error)
    starts.should eq([2])
    input.start.should eq(1)
  end

  it "does not retry an anchored split or pass the original end in reverse" do
    anchored = Regex::Automata::Input.new("☃").range(0...2).anchored(Regex::Automata::Anchored::Yes)
    calls = 0
    result = Regex::Automata::Empty.skip_splits_rev(anchored, Regex::Automata::HalfMatch.must(0, 2)) do |_retry|
      calls += 1
      Regex::Automata::HalfMatch.must(0, 0)
    end
    result.should be_nil
    calls.should eq(0)

    input = Regex::Automata::Input.new("☃").range(0...2)
    ends = [] of Int32
    result = Regex::Automata::Empty.skip_splits_rev(input, Regex::Automata::HalfMatch.must(0, 2)) do |retry|
      ends << retry.end
      Regex::Automata::HalfMatch.must(0, 0)
    end
    result.should eq(Regex::Automata::HalfMatch.must(0, 0))
    ends.should eq([1])
    input.end.should eq(2)
  end

  it "rejects an anchored dense empty match inside a codepoint" do
    dfa = Regex::Automata::DFA::DFA.new("")
    input = Regex::Automata::Input.new("☃").range(1...3).anchored(Regex::Automata::Anchored::Yes)

    dfa.try_search_fwd(input).should be_nil
  end

  it "retries an unanchored dense search until a valid UTF-8 boundary" do
    dfa = Regex::Automata::DFA::DFA.new("")
    input = Regex::Automata::Input.new("☃").range(1...3)

    dfa.try_search_fwd(input).should eq(
      Regex::Automata::HalfMatch.new(Regex::Automata::PatternID::ZERO, 3)
    )
  end

  it "applies the same rule to forward hybrid searches" do
    dfa = Regex::Automata::Hybrid::Builder.new.build("")
    cache = dfa.create_cache
    inside = Regex::Automata::Input.new("☃").range(1...3)

    dfa.try_search_fwd(cache, inside.clone.anchored(Regex::Automata::Anchored::Yes)).should be_nil
    dfa.try_search_fwd(cache, inside).should eq(Regex::Automata::HalfMatch.must(0, 3))
  end

  it "applies the same rule to PikeVM and backtracker searches" do
    input = Regex::Automata::Input.new("☃").range(1...3)
    anchored = input.clone.anchored(Regex::Automata::Anchored::Yes)
    expected = Regex::Automata::Match.must(0, 3...3)

    pike = Regex::Automata::NFA::PikeVM.new("")
    pike_cache = pike.create_cache
    pike.find(pike_cache, anchored).should be_nil
    pike.find(pike_cache, input).should eq(expected)

    backtrack = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("")
    backtrack_cache = backtrack.create_cache
    backtrack.try_find(backtrack_cache, anchored).should be_nil
    backtrack.try_find(backtrack_cache, input).should eq(expected)
  end

  it "applies the reverse UTF-8 boundary rule to dense and hybrid DFAs" do
    input = Regex::Automata::Input.new("☃").range(0...2)
    anchored = input.clone.anchored(Regex::Automata::Anchored::Yes)
    expected = Regex::Automata::HalfMatch.must(0, 0)

    dense = Regex::Automata::DFA::DFA.builder
      .thompson { |config| config.reverse(true) }
      .build("")
    dense.try_search_rev(anchored).should be_nil
    dense.try_search_rev(input).should eq(expected)

    hybrid = Regex::Automata::Hybrid::Builder.new
      .thompson(Regex::Automata::NFA::NFA.config.reverse(true))
      .build("")
    cache = hybrid.create_cache
    hybrid.try_search_rev(cache, anchored).should be_nil
    hybrid.try_search_rev(cache, input).should eq(expected)
  end

  it "skips ASCII non-word boundaries inside a later UTF-8 codepoint" do
    pattern = "(?-u:\\B)"
    haystack = "a☃"
    expected = Regex::Automata::Match.must(0, 4...4)

    pike = Regex::Automata::NFA::PikeVM.new(pattern)
    pike.find(pike.create_cache, haystack).should eq(expected)

    backtrack = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new(pattern)
    backtrack.try_find(backtrack.create_cache, haystack).should eq(expected)

    dense = Regex::Automata::DFA::DFA.new(pattern)
    dense.try_search_fwd(Regex::Automata::Input.new(haystack)).should eq(
      Regex::Automata::HalfMatch.must(0, 4)
    )

    sparse = dense.to_sparse
    sparse.try_search_fwd(Regex::Automata::Input.new(haystack)).should eq(
      Regex::Automata::HalfMatch.must(0, 4)
    )

    hybrid = Regex::Automata::Hybrid::Builder.new.build(pattern)
    hybrid.try_search_fwd(hybrid.create_cache, Regex::Automata::Input.new(haystack)).should eq(
      Regex::Automata::HalfMatch.must(0, 4)
    )
  end

  it "does not search past bounded input for a valid empty match" do
    input = Regex::Automata::Input.new("☃z").range(1...2)
    dense = Regex::Automata::DFA::DFA.new("")
    hybrid = Regex::Automata::Hybrid::Builder.new.build("")
    pike = Regex::Automata::NFA::PikeVM.new("")
    backtrack = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("")

    dense.try_search_fwd(input).should be_nil
    hybrid.try_search_fwd(hybrid.create_cache, input).should be_nil
    pike.find(pike.create_cache, input).should be_nil
    backtrack.try_find(backtrack.create_cache, input).should be_nil
  end

  it "preserves a non-empty match when the pattern also permits empty matches" do
    input = Regex::Automata::Input.new("a☃z")
    dense = Regex::Automata::DFA::DFA.new("a*")
    hybrid = Regex::Automata::Hybrid::Builder.new.build("a*")
    pike = Regex::Automata::NFA::PikeVM.new("a*")
    backtrack = Regex::Automata::NFA::Backtrack::BoundedBacktracker.new("a*")

    dense.try_search_fwd(input).should eq(Regex::Automata::HalfMatch.must(0, 1))
    hybrid.try_search_fwd(hybrid.create_cache, input).should eq(Regex::Automata::HalfMatch.must(0, 1))
    pike.find(pike.create_cache, input).should eq(Regex::Automata::Match.must(0, 0...1))
    backtrack.try_find(backtrack.create_cache, input).should eq(Regex::Automata::Match.must(0, 0...1))
  end
end
