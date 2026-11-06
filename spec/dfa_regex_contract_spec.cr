require "./spec_helper"

# A valid minimal never-match dense automaton with call-count observation.
# This characterizes regex.rs::try_search's single-forward-search contract.
class RegexWrapperMissDFA < Regex::Automata::DFA::DFA
  getter forward_calls : Int32 = 0

  def initialize
    states = Array.new(2) { |index| Regex::Automata::DFA::State.new(Regex::Automata::StateID.new(index), 1) }
    super(states, nil, Regex::Automata::StateID::ZERO, Regex::Automata::ByteClasses.empty)
  end

  def try_search_fwd(input : Regex::Automata::Input) : Regex::Automata::HalfMatch? | Regex::Automata::MatchError
    @forward_calls += 1
    super(input)
  end
end

describe "pinned DFA regex wrapper contracts" do
  it "performs exactly one forward search after an unanchored miss" do
    forward = RegexWrapperMissDFA.new
    regex = Regex::Automata::DFA::Regex.builder.build_from_dfas(forward, Regex::Automata::DFA::DFA.never_match)
    input = Regex::Automata::Input.new("a long haystack with no matching pattern")
    regex.try_search(input).should be_nil
    forward.forward_calls.should eq(1)
    input.start.should eq(0)
  end

  it "derives always-anchored and empty flags from the NFA, not the supported start kind" do
    anchored_only = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.start_kind(Regex::Automata::StartKind::Anchored))
      .build("abc")
    anchored_only.is_always_start_anchored?.should be_false
    anchored_only.to_sparse.is_always_start_anchored?.should be_false
    Regex::Automata::DFA::DFA.new("(?-u:\\b\\B)").has_empty?.should be_true
  end

  it "preserves the reverse-must-match assertion for incompatible supplied DFAs" do
    forward = Regex::Automata::DFA::DFA.new("a")
    reverse = Regex::Automata::DFA::DFA.never_match
    regex = Regex::Automata::DFA::Regex.builder.build_from_dfas(forward, reverse)
    expect_raises(Exception, /reverse search must match if forward search does/) do
      regex.try_search(Regex::Automata::Input.new("a"))
    end
  end

  it "preserves the same-pattern assertion for incompatible supplied DFAs" do
    forward = Regex::Automata::DFA::DFA.new("a")
    reverse = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::DFA::DFA.config.start_kind(Regex::Automata::StartKind::Anchored).match_kind(Regex::Automata::MatchKind::All))
      .thompson { |compiler| compiler.reverse(true) }
      .build_many(["z", "a"])
    regex = Regex::Automata::DFA::Regex.builder.build_from_dfas(forward, reverse)
    expect_raises(Exception, /forward and reverse search must match same pattern/) do
      regex.try_search(Regex::Automata::Input.new("a"))
    end
  end
end

describe "DFA wrapper builder state" do
  it "mutates dense/syntax/Thompson builder configuration like Rust's &mut Builder" do
    builder = Regex::Automata::DFA::Regex.builder
    builder.dense(Regex::Automata::DFA::DFA.config.quit('x'.ord.to_u8, true))
    builder.build("abcd").try_search(Regex::Automata::Input.new("abcx")).should be_a(Regex::Automata::MatchError)
    builder = Regex::Automata::DFA::Regex.builder
    builder.syntax { |parser| parser.case_insensitive(true) }
    builder.build("a").is_match("A").should be_true
    builder = Regex::Automata::DFA::Regex.builder
    builder.thompson { |compiler| compiler.utf8(false) }
    builder.build("a").forward.is_utf8?.should be_false
  end

  it "retains structural NFA empty capability for contradictory look assertions" do
    Regex::Automata::DFA::DFA.new("(?-u:\\b\\B)").has_empty?.should be_true
  end

  it "forcefully disables capture construction even when explicitly enabled" do
    pattern = "(a)" * 100
    none = Regex::Automata::HirCompilerConfig.new.which_captures(Regex::Automata::NFA::WhichCaptures::None)
    forward_size = Regex::Automata::HirCompiler.new(none).build(pattern).memory_usage
    reverse_size = Regex::Automata::HirCompiler.new(none.reverse(true)).build(pattern).memory_usage
    limit = Math.max(forward_size, reverse_size) * 2
    builder = Regex::Automata::DFA::Regex.builder.thompson do |compiler|
      compiler.which_captures(Regex::Automata::NFA::WhichCaptures::All).nfa_size_limit(limit.to_i64)
    end
    builder.build(pattern).find("a" * 100).should eq(Regex::Automata::Match.must(0, 0, 100))
  end
end

describe "DFA wrapper Input and collection APIs" do
  {false, true}.each do |sparse|
    it "ports Input, reusable pattern slices and sparse factory behavior (sparse=#{sparse})" do
      builder = Regex::Automata::DFA::Regex.builder
      patterns = ["[a-z]+", "[0-9]+"].each
      regex = sparse ? builder.build_many_sparse(patterns) : builder.build_many(patterns)
      regex.pattern_len.should eq(2)
      regex.find("123").should eq(Regex::Automata::Match.must(1, 0, 3))
      input = Regex::Automata::Input.new("z123x").range(1...4)
      regex.find(input).should eq(Regex::Automata::Match.must(1, 1, 4))
      input.start.should eq(1)
      input.end.should eq(4)
      if sparse
        regex.forward.should be_a(Regex::Automata::DFA::Sparse::DFA)
        regex.reverse.should be_a(Regex::Automata::DFA::Sparse::DFA)
      end
    end

    it "ports the constructor, iterator and pattern-count doctests (sparse=#{sparse})" do
      regex = sparse ? Regex::Automata::DFA::Regex.new_sparse("foo[0-9]+bar") : Regex::Automata::DFA::Regex.new("foo[0-9]+bar")
      regex.find("foo12345bar").should eq(Regex::Automata::Match.must(0, 0, 11))
      regex.is_match("foobar").should be_false
      patterns = ["[a-z]+", "[0-9]+"]
      regex = sparse ? Regex::Automata::DFA::Regex.new_many_sparse(patterns) : Regex::Automata::DFA::Regex.new_many(patterns)
      iterator = regex.find_iter("abc 1 foo 4567 0 quux")
      expected = [{0, 0, 3}, {1, 4, 5}, {0, 6, 9}, {1, 10, 14}, {1, 15, 16}, {0, 17, 21}]
      expected.each { |pattern, start, finish| iterator.next.should eq(Regex::Automata::Match.must(pattern, start, finish)) }
      iterator.next.should eq(Iterator::Stop::INSTANCE)
      iterator.next.should eq(Iterator::Stop::INSTANCE)
      regex = sparse ? Regex::Automata::DFA::Regex.new_sparse("foo[0-9]+") : Regex::Automata::DFA::Regex.new("foo[0-9]+")
      regex.find("zzzfoo12345zzz").should eq(Regex::Automata::Match.must(0, 3, 11))
      regex.find_iter("foo1 foo12 foo123").to_a.should eq([
        Regex::Automata::Match.must(0, 0, 4), Regex::Automata::Match.must(0, 5, 10), Regex::Automata::Match.must(0, 11, 17),
      ])
      regex = sparse ? Regex::Automata::DFA::Regex.new_many_sparse(["[a-z]+", "[0-9]+", "\\w+"]) : Regex::Automata::DFA::Regex.new_many(["[a-z]+", "[0-9]+", "\\w+"])
      regex.pattern_len.should eq(3)
    end

    it "ports the binary syntax/Thompson and quit-error doctests (sparse=#{sparse})" do
      builder = Regex::Automata::DFA::Regex.builder
        .syntax { |parser| parser.utf8(false) }
        .thompson { |compiler| compiler.utf8(false) }
      regex = sparse ? builder.build_sparse("foo(?-u:[^b])ar.*") : builder.build("foo(?-u:[^b])ar.*")
      haystack = Bytes[0xFE, 0x66, 0x6F, 0x6F, 0xFF, 0x61, 0x72, 0x7A, 0x7A, 0xE2, 0x98, 0xFF, 0x0A]
      regex.find(haystack).should eq(Regex::Automata::Match.must(0, 1, 9))
      builder = Regex::Automata::DFA::Regex.builder.dense(Regex::Automata::DFA::DFA.config.quit('\n'.ord.to_u8, true))
      regex = sparse ? builder.build_sparse("foo\\p{any}+bar") : builder.build("foo\\p{any}+bar")
      regex.try_search(Regex::Automata::Input.new("foo\nbar")).should eq(Regex::Automata::MatchError.quit('\n'.ord.to_u8, 3))
    end

    it "preserves earliest-forward/longest-reverse and empty-match iteration (sparse=#{sparse})" do
      patterns = ["ab", "b"]
      regex = sparse ? Regex::Automata::DFA::Regex.new_many_sparse(patterns) : Regex::Automata::DFA::Regex.new_many(patterns)
      input = Regex::Automata::Input.new("ab").earliest(true)
      regex.find(input).should eq(Regex::Automata::Match.must(0, 0, 2))
      input.get_earliest.should be_true
      regex = sparse ? Regex::Automata::DFA::Regex.new_sparse("") : Regex::Automata::DFA::Regex.new("")
      iterator = regex.find_iter("☃")
      iterator.next.should eq(Regex::Automata::Match.must(0, 0, 0))
      iterator.to_a.should eq([Regex::Automata::Match.must(0, 3, 3)])
      regex.find(Regex::Automata::Input.new("☃").range(1...2)).should be_nil
    end

    it "preserves quit errors in find/is_match/iterator and fallible search (sparse=#{sparse})" do
      builder = Regex::Automata::DFA::Regex.builder.dense(Regex::Automata::DFA::DFA.config.quit('x'.ord.to_u8, true))
      regex = sparse ? builder.build_sparse("abcd") : builder.build("abcd")
      regex.try_search(Regex::Automata::Input.new("abcx")).should eq(Regex::Automata::MatchError.quit('x'.ord.to_u8, 3))
      expect_raises(Exception) { regex.find("abcx") }
      expect_raises(Exception) { regex.is_match("abcx") }
      expect_raises(Exception) { regex.find_iter("abcx").next }
      regex = sparse ? builder.build_sparse("a") : builder.build("a")
      regex.is_match("ayx").should be_true
      regex.try_search(Regex::Automata::Input.new("ayx")).should eq(Regex::Automata::MatchError.quit('x'.ord.to_u8, 2))
    end
  end

  it "preserves pattern counts for duplicate and impossible patterns through transforms and sparse conversion" do
    {false, true}.each do |minimize|
      {false, true}.each do |accelerate|
        patterns = ["a", "a", "(?-u:\\b\\B)"]
        builder = Regex::Automata::DFA::Regex.builder.dense(Regex::Automata::DFA::DFA.config.minimize(minimize).accelerate(accelerate))
        {builder.build_many(patterns), builder.build_many_sparse(patterns)}.each do |regex|
          regex.pattern_len.should eq(3)
          regex.find("a").should eq(Regex::Automata::Match.must(0, 0, 1))
          forward = case dfa = regex.forward
                    when Regex::Automata::DFA::DFA
                      Regex::Automata::DFA::DFA.from_bytes(dfa.to_bytes_native_endian[0])[0]
                    when Regex::Automata::DFA::Sparse::DFA
                      Regex::Automata::DFA::Sparse::DFA.from_bytes(dfa.to_bytes_native_endian)[0]
                    else
                      raise "unsupported DFA implementation"
                    end
          reverse = case dfa = regex.reverse
                    when Regex::Automata::DFA::DFA
                      Regex::Automata::DFA::DFA.from_bytes(dfa.to_bytes_native_endian[0])[0]
                    when Regex::Automata::DFA::Sparse::DFA
                      Regex::Automata::DFA::Sparse::DFA.from_bytes(dfa.to_bytes_native_endian)[0]
                    else
                      raise "unsupported DFA implementation"
                    end
          roundtrip = Regex::Automata::DFA::Regex.builder.build_from_dfas(forward, reverse)
          roundtrip.pattern_len.should eq(3)
          roundtrip.find("a").should eq(Regex::Automata::Match.must(0, 0, 1))
        end
      end
    end
  end
end

describe "direct Rust-style wrapper configuration" do
  it "supports configuration values as well as blocks and preserves unspecified Thompson settings" do
    builder = Regex::Automata::DFA::Regex.builder
    builder.syntax(Regex::Automata::Syntax::Config.new.case_insensitive(true))
    builder.thompson(Regex::Automata::HirCompilerConfig.new.utf8(false))
    builder.thompson(Regex::Automata::HirCompilerConfig.new.shrink(true))
    regex = builder.build("a")
    regex.is_match("A").should be_true
    regex.forward.is_utf8?.should be_false
    builder.build_sparse("a").is_match("A").should be_true
  end
end

describe "DFA wrapper clones" do
  it "isolates cloned builder configuration and retains unspecified settings" do
    original = Regex::Automata::DFA::Regex.builder
      .syntax(Regex::Automata::Syntax::Config.new.case_insensitive(true))
      .thompson(Regex::Automata::HirCompilerConfig.new.utf8(false))
    copy = original.clone
    copy.syntax(Regex::Automata::Syntax::Config.new.case_insensitive(false))
    original.build("a").is_match("A").should be_true
    copy.build("a").is_match("A").should be_false
    original.build("a").forward.is_utf8?.should be_false
    copy.build("a").forward.is_utf8?.should be_false
  end

  {false, true}.each do |sparse|
    it "copies both owned automata when cloning a regex (sparse=#{sparse})" do
      original = sparse ? Regex::Automata::DFA::Regex.new_sparse("a+") : Regex::Automata::DFA::Regex.new("a+")
      copy = original.clone
      copy.forward.same?(original.forward).should be_false
      copy.reverse.same?(original.reverse).should be_false
      copy.find("zaaa").should eq(Regex::Automata::Match.must(0, 1, 4))
      copy.pattern_len.should eq(original.pattern_len)
    end
  end
end
