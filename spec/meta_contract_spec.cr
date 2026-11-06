require "./spec_helper"

# Source-derived tests for meta/regex.rs and wrappers.rs; suite results use
# the existing vendor fixtures in meta_vendor_suite_spec.cr.
class Regex::Automata::Meta::Regex
  def meta_impossible_for_spec?(input : ::Regex::Automata::Input) : Bool
    impossible_input?(input)
  end

  def meta_pool_for_spec : ::Regex::Automata::Pool(::Regex::Automata::Meta::Cache)
    @pool
  end
end

describe "pinned Meta facade contracts" do
  it "suppresses offset APIs with WhichCaptures::None while preserving existence and pattern sets" do
    config = Regex::Automata::Meta::Regex.config.which_captures(Regex::Automata::NFA::WhichCaptures::None)
    re = Regex::Automata::Meta::Regex.builder.configure(config).build("(a)")
    input = Regex::Automata::Input.new("a")
    cache = re.create_cache
    re.is_match(input).should be_true
    re.find(input).should be_nil
    re.search(input).should be_nil
    re.search_half(input).should be_nil
    re.search_with(cache, input).should be_nil
    re.search_half_with(cache, input).should be_nil
    slots = [7, 7, 7, 7] of Int32?
    re.search_slots_with(cache, input, slots).should be_nil
    slots.should eq([7, 7, 7, 7])
    captures = re.create_captures
    re.captures(input, captures)
    captures.pattern.should be_nil
    re.find_iter(input).to_a.should be_empty
    patterns = Regex::Automata::PatternSet.new(1)
    re.which_overlapping_matches(input, patterns)
    patterns.iter.to_a.should eq([Regex::Automata::PatternID.new(0)])
    # Even a literal bypass inherits this facade guard in Rust.
    literal = Regex::Automata::Meta::Regex.builder.configure(config).build("a")
    literal.is_match("a").should be_true
    literal.find("a").should be_nil
  end

  it "uses minimum and fully anchored maximum lengths for impossible input" do
    re = Regex::Automata::Meta::Regex.new("[a-z]{3}")
    re.meta_impossible_for_spec?(Regex::Automata::Input.new("ab")).should be_true
    re.meta_impossible_for_spec?(Regex::Automata::Input.new("abcd")).should be_false
    re = Regex::Automata::Meta::Regex.new("[a-z]{3}$")
    re.meta_impossible_for_spec?(Regex::Automata::Input.new("abcd").anchored(Regex::Automata::Anchored::Yes)).should be_true
    re.meta_impossible_for_spec?(Regex::Automata::Input.new("abcd")).should be_false
    re = Regex::Automata::Meta::Regex.new("^[a-z]{3}$")
    re.meta_impossible_for_spec?(Regex::Automata::Input.new("abcd")).should be_true
  end

  it "does not mutate caller slots when an impossible-input guard returns early" do
    re = Regex::Automata::Meta::Regex.new("^a$")
    slots = [9, 9] of Int32?
    re.search_slots_with(re.create_cache, Regex::Automata::Input.new("za").range(1...2), slots).should be_nil
    slots.should eq([9, 9])
  end

  it "accepts the configured one-pass limit without narrowing to Int32" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.onepass_size_limit(1_i64 << 32)).build("(a)")
    re.core_onepass.should_not be_nil
    re.is_match("a").should be_true
  end

  it "retains typed syntax/NFA causes through Meta build errors" do
    syntax = expect_raises(Regex::Automata::Meta::BuildError) do
      Regex::Automata::Meta::Regex.new_many(["a", "("])
    end
    syntax.pattern.should eq(Regex::Automata::PatternID.new(1))
    syntax.cause.should_not be_nil
    syntax.syntax_error.should be_a(Exception)
    limited = expect_raises(Regex::Automata::Meta::BuildError) do
      Regex::Automata::Meta::Regex.builder.configure(Regex::Automata::Meta::Regex.config.nfa_size_limit(0_i64)).build("a+")
    end
    limited.cause.should be_a(Regex::Automata::NFA::BuildError)
    limited.size_limit.should eq(0)
  end

  it "splits the complete haystack around matches restricted by Input bounds" do
    re = Regex::Automata::Meta::Regex.new(" ")
    input = Regex::Automata::Input.new("a b c d").range(2...5)
    split = re.split(input)
    split.next.should eq(Regex::Automata::Span.new(0, 3))
    split.input.start.should eq(4)
    split.next.should eq(Regex::Automata::Span.new(4, 7))
    split.next.should eq(Iterator::Stop::INSTANCE)
  end
end

describe "pinned Meta clone and syntax contracts" do
  it "clones compiled engines with independent pools and mutable caches" do
    configs = [
      Regex::Automata::Meta::Regex.config,
      Regex::Automata::Meta::Regex.config.dfa(false),
      Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false),
      Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false),
      Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false).backtrack(false),
    ]
    configs.each do |config|
      re = Regex::Automata::Meta::Regex.builder.configure(config).build("([a-z]+)([0-9]+)")
      cache = re.create_cache
      caps = re.create_captures
      re.search_captures_with(cache, Regex::Automata::Input.new("abc123"), caps)
      copied_cache = cache.clone
      # Rust Vec::clone copies live lengths, so spare capacity need not match.
      copied_cache.memory_usage.should be > 0
      copied_cache.core_capmatches.should_not be(cache.core_capmatches)
      copied = re.clone
      copied.nfa.should be(re.nfa)
      copied.meta_pool_for_spec.should_not be(re.meta_pool_for_spec)
      re.search_captures_with(cache, Regex::Automata::Input.new("x9"), caps)
      other = copied.create_captures
      copied.search_captures_with(copied_cache, Regex::Automata::Input.new("def456"), other)
      other.get_group(1).should eq(Regex::Automata::Span.new(0, 3))
      caps.get_group(1).should eq(Regex::Automata::Span.new(0, 1))
    end
  end

  it "clones builders/configuration without sharing subsequent configuration changes" do
    config = Regex::Automata::Meta::Regex.config.dfa(false)
    config.clone.get_dfa.should be_false
    builder = Regex::Automata::Meta::Regex.builder.configure(config)
    copied = builder.clone
    copied.syntax(Regex::Automata::Syntax::Config.new.case_insensitive(true))
    builder.build("a").is_match("A").should be_false
    copied.build("a").is_match("A").should be_true
  end

  it "keeps parser line terminators independent from the search look matcher" do
    re = Regex::Automata::Meta::Regex.builder
      .syntax(Regex::Automata::Syntax::Config.new.line_terminator('X'.ord.to_u8)).build(".")
    re.is_match("X").should be_false
    re.is_match("\n").should be_true
    ["(.)", "(?:.)", "(?i:.)", "((?:.))"].each do |pattern|
      grouped = Regex::Automata::Meta::Regex.builder
        .syntax(Regex::Automata::Syntax::Config.new.line_terminator('X'.ord.to_u8)).build(pattern)
      grouped.is_match("X").should be_false
      grouped.is_match("\n").should be_true
    end
  end

  it "accepts Rust's input-first splitn order and uses the whole haystack tail" do
    re = Regex::Automata::Meta::Regex.new(" ")
    input = Regex::Automata::Input.new("a b c d").range(2...5)
    re.splitn(input, 2).to_a.should eq([Regex::Automata::Span.new(0, 3), Regex::Automata::Span.new(4, 7)])
    re.splitn(input, 0).to_a.should be_empty
    re.splitn(input, 5).to_a.should eq(re.split(input).to_a)
  end
end

describe "pinned Meta builder ordering and pool defaults" do
  it "reports all AST errors before translating an earlier pattern to HIR" do
    error = expect_raises(Regex::Automata::Meta::BuildError) do
      Regex::Automata::Meta::Regex.new_many(["\\p{DefinitelyNotAProperty}", "("])
    end
    error.pattern.should eq(Regex::Automata::PatternID.new(1))
    error.syntax_error.should be_a(Regex::Syntax::AST::Error)
  end

  it "defaults pool capacity to available CPUs and retains explicit zero in Config" do
    Regex::Automata::Meta::Regex.config.get_pool_capacity.should eq(System.cpu_count)
    Regex::Automata::Meta::Regex.config.pool_capacity(0).get_pool_capacity.should eq(0)
  end

  it "stops a reverse DFA at a dead state without taking EOI from its predecessor" do
    re = Regex::Automata::Meta::Regex.builder.syntax(Regex::Automata::Syntax::Config.new.unicode(false).utf8(false)).build("\\B$")
    reverse = re.core_dfa.not_nil!.reverse
    reverse.try_search_rev(Regex::Automata::Input.new("x").anchored(Regex::Automata::Anchored::Yes)).should be_nil
    re.is_match("x").should be_false
  end
end

describe "pinned Meta cache reset contracts" do
  it "retains Rust's missing optional-cache reset failure" do
    config = Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false)
    old = Regex::Automata::Meta::Regex.builder.configure(config).build("[a-z]+")
    targets = [
      Regex::Automata::Meta::Regex.builder.configure(Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false)).build("([a-z]+)"),
      Regex::Automata::Meta::Regex.builder.configure(Regex::Automata::Meta::Regex.config.dfa(false)).build("[a-z]+"),
    ]
    targets.each do |target|
      expect_raises(Exception) { old.create_cache.reset(target) }
    end
  end
end

describe "pinned literal strategy anchoring" do
  it "uses the literal prefix for every anchored mode as Rust Pre does" do
    re = Regex::Automata::Meta::Regex.new("a")
    input = Regex::Automata::Input.new("a").anchored(Regex::Automata::Anchored::Pattern, Regex::Automata::PatternID.new(1))
    re.find(input).should eq(Regex::Automata::Match.must(0, 0...1))
  end
end

describe "pinned literal output slots" do
  it "writes only the implicit pair and leaves slots untouched on a miss" do
    re = Regex::Automata::Meta::Regex.new("a")
    cache = re.create_cache
    slots = [7, 7, 7, 7] of Int32?
    re.search_slots_with(cache, Regex::Automata::Input.new("a"), slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 1, 7, 7])
    partial = [7] of Int32?
    re.search_slots_with(cache, Regex::Automata::Input.new("a"), partial).should eq(Regex::Automata::PatternID.new(0))
    partial.should eq([0])
    re.search_slots_with(cache, Regex::Automata::Input.new("b"), slots).should be_nil
    slots.should eq([0, 1, 7, 7])
  end
end

class Regex::Automata::Meta::Cache
  def meta_pike_allocated_for_spec? : Bool
    !@cache.nil?
  end
end

describe "pinned reverse capture rerun" do
  it "uses the Core nofail order after an anchored reverse hit" do
    re = Regex::Automata::Meta::Regex.new("([a-z]+)$")
    re.core_onepass.should_not be_nil
    cache = re.create_cache
    caps = re.create_captures
    re.search_captures_with(cache, Regex::Automata::Input.new("abc"), caps)
    caps.get_group(1).should eq(Regex::Automata::Span.new(0, 3))
    cache.meta_pike_allocated_for_spec?.should be_false
  end
end

describe "pinned literal reset no-op" do
  it "preserves the lazy PikeVM factory as well as allocated scratch" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false).backtrack(false)).build("[a-z]+")
    cache = re.create_cache
    cache.reset(Regex::Automata::Meta::Regex.new("a"))
    re.search_with(cache, Regex::Automata::Input.new("abc")).should eq(Regex::Automata::Match.must(0, 0...3))
  end
end
