require "./spec_helper"

# White-box assertion for Rust's private Strategy::new selector tests.
class Regex::Automata::Meta::Regex
  def literal_bypass_for_spec? : Bool
    !@literal_prefilter.nil? && !@literal_pattern_ids.nil?
  end

  def literal_prefilter_for_spec : ::Regex::Automata::Prefilter?
    @literal_prefilter
  end

  def core_engines_for_spec : {Bool, Bool, Bool, Bool}
    {!@core_dfa.nil?, !@core_hybrid.nil?, !@core_onepass.nil?, !@core_backtrack.nil?}
  end
end

class Regex::Automata::Prefilter
  def aho_for_spec? : Bool
    !@aho.nil?
  end
end

describe "pinned Rust meta Core dispatch" do
  it "selects Core and admits the full DFA for a small nonliteral pattern" do
    re = Regex::Automata::Meta::Regex.new("[a-z]+")
    re.literal_bypass_for_spec?.should be_false
    re.core_engines_for_spec[0].should be_true
    cache = re.create_cache
    re.search_with(cache, Regex::Automata::Input.new("123abc")).should eq(Regex::Automata::Match.must(0, 3...6))
    cache.pike_scratch_allocated_for_spec?.should be_false
    re.is_match_with(cache, Regex::Automata::Input.new("123abc").earliest(true)).should be_true
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "selects lazy DFA when full DFA is disabled and no reverse strategy applies" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).auto_prefilter(false))
      .build("[a-z]+")
    re.core_engines_for_spec[0].should be_false
    re.core_engines_for_spec[1].should be_true
    cache = re.create_cache
    re.search_with(cache, Regex::Automata::Input.new("123abc")).should eq(Regex::Automata::Match.must(0, 3...6))
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "uses the Rust nofail order for anchored captures when DFAs are disabled" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false))
      .build("([a-z]+)")
    re.core_engines_for_spec[2].should be_true
    re.core_engines_for_spec[3].should be_true
    cache = re.create_cache
    slots = [nil, nil, nil, nil] of Int32?
    re.search_slots_with(cache, Regex::Automata::Input.new("abc").anchored(Regex::Automata::Anchored::Yes), slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 3, 0, 3])
    cache.raw_cache.setup_calls_for_spec.should eq(0)
  end

  it "uses the bounded backtracker before PikeVM when OnePass is disabled" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false))
      .build("([a-z]+)")
    re.core_engines_for_spec.should eq({false, false, false, true})
    cache = re.create_cache
    slots = [nil, nil, nil, nil] of Int32?
    re.search_slots_with(cache, Regex::Automata::Input.new("abc"), slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 3, 0, 3])
    cache.raw_cache.setup_calls_for_spec.should eq(0)
  end

  it "uses PikeVM when all optional Core engines are disabled" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false).hybrid(false).onepass(false).backtrack(false))
      .build("([a-z]+)")
    re.core_engines_for_spec.should eq({false, false, false, false})
    cache = re.create_cache
    re.search_with(cache, Regex::Automata::Input.new("123abc")).should eq(Regex::Automata::Match.must(0, 3...6))
    cache.raw_cache.setup_calls_for_spec.should be > 0
    re.is_match_with(cache, Regex::Automata::Input.new("123abc").earliest(true)).should be_true
  end

  it "reruns capture extraction on the matched span after a full-DFA hit" do
    re = Regex::Automata::Meta::Regex.new("([a-z]+)([0-9]+)")
    re.core_engines_for_spec[0].should be_true
    cache = re.create_cache
    slots = Array(Int32?).new(6, nil)
    re.search_slots_with(cache, Regex::Automata::Input.new("xxabc123!"), slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 8, 0, 5, 5, 8])
    cache.raw_cache.setup_calls_for_spec.should eq(0)
  end

  it "preserves input span and anchoring in full-DFA overlapping searches" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa_size_limit(1_000_000_i64))
      .build_many(["[a-z]+", "[0-9]+"])
    re.core_engines_for_spec[0].should be_true
    patset = Regex::Automata::PatternSet.new(2)
    re.which_overlapping_matches(
      Regex::Automata::Input.new("abc123xyz").span(3...6).anchored(Regex::Automata::Anchored::Yes),
      patset
    )
    patset.iter.to_a.should eq([Regex::Automata::PatternID.new(1)])
  end

  it "retries with a nofail engine when a full DFA quits on a Unicode word boundary" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa_size_limit(1_000_000_i64))
      .build("\\bélan\\b")
    re.core_engines_for_spec[0].should be_true
    input = Regex::Automata::Input.new("élan")
    re.core_dfa.not_nil!.try_search(input).should be_a(Regex::Automata::MatchError)
    re.find("élan").should eq(Regex::Automata::Match.must(0, 0...5))
  end

  it "retries with a nofail engine when a lazy DFA quits on a Unicode word boundary" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false))
      .build("\\bélan\\b")
    re.core_engines_for_spec[1].should be_true
    input = Regex::Automata::Input.new("élan")
    raw = re.core_hybrid.not_nil!
    raw.try_search(raw.create_cache, input).should be_a(Regex::Automata::MatchError)
    re.find("élan").should eq(Regex::Automata::Match.must(0, 0...5))
  end
end

class Regex::Automata::NFA::PikeVM::Cache
  getter setup_calls_for_spec = 0

  def setup_search(captures_slot_len : Int32) : Nil
    @setup_calls_for_spec += 1
    previous_def(captures_slot_len)
  end
end

describe "pinned Rust meta literal strategy selection" do
  it "uses a literal engine only for exact single-pattern leftmost-first HIRs" do
    Regex::Automata::Meta::Regex.new("a").literal_bypass_for_spec?.should be_true
    Regex::Automata::Meta::Regex.new("a|b").literal_bypass_for_spec?.should be_true
    Regex::Automata::Meta::Regex.new("Sherlock").literal_bypass_for_spec?.should be_true
    Regex::Automata::Meta::Regex.new("a+").literal_bypass_for_spec?.should be_false
    Regex::Automata::Meta::Regex.new("").literal_bypass_for_spec?.should be_false
    Regex::Automata::Meta::Regex.new_many(["a", "b"]).literal_bypass_for_spec?.should be_false
    Regex::Automata::Meta::Regex.new_many(["a|b", "c|d"]).literal_bypass_for_spec?.should be_false
    Regex::Automata::Meta::Regex.new("(a)").literal_bypass_for_spec?.should be_false
    Regex::Automata::Meta::Regex.new("(?:a)").literal_bypass_for_spec?.should be_true
    Regex::Automata::Meta::Regex.new("(){0}a").literal_bypass_for_spec?.should be_true
    Regex::Automata::Meta::Regex.new("a\\b").literal_bypass_for_spec?.should be_false
    all = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.match_kind(Regex::Automata::MatchKind::All))
      .build("a")
    all.literal_bypass_for_spec?.should be_false
  end

  it "respects Rust's disabled-auto and caller-prefilter priority" do
    auto_off = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.auto_prefilter(false))
      .build("Sherlock")
    auto_off.literal_bypass_for_spec?.should be_false

    pre = Regex::Automata::Prefilter.new(Regex::Automata::MatchKind::LeftmostFirst, ["Sherlock"]).not_nil!
    explicit = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.prefilter(pre))
      .build("Sherlock")
    explicit.literal_bypass_for_spec?.should be_false
    explicit.find("Sherlock").should eq(Regex::Automata::Match.must(0, 0...8))
  end

  it "uses Rust's 3000-literal alternation threshold after prefix extraction gives up" do
    small = Array.new(2_999) { |i| "needle#{i.to_s.rjust(5, '0')}" }.join("|")
    large = Array.new(3_000) { |i| "needle#{i.to_s.rjust(5, '0')}" }.join("|")

    Regex::Automata::Meta::Regex.new(small).literal_bypass_for_spec?.should be_false
    Regex::Automata::Meta::Regex.new(large).literal_bypass_for_spec?.should be_true
  end

  it "does not bypass for explicit captures, look-around, multiple patterns, or MatchKind::All at the large threshold" do
    large = Array.new(3_000) { |i| "needle#{i.to_s.rjust(5, '0')}" }.join("|")
    Regex::Automata::Meta::Regex.new("(#{large})").literal_bypass_for_spec?.should be_false
    Regex::Automata::Meta::Regex.new("(?:#{large})\\b").literal_bypass_for_spec?.should be_false
    Regex::Automata::Meta::Regex.new_many([large, large]).literal_bypass_for_spec?.should be_false
    all = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.match_kind(Regex::Automata::MatchKind::All))
      .build(large)
    all.literal_bypass_for_spec?.should be_false
  end

  it "uses Rust's Aho-Corasick path and conservative acceleration signal for huge alternations" do
    large = Array.new(3_000) { |i| "needle#{i.to_s.rjust(5, '0')}" }.join("|")
    re = Regex::Automata::Meta::Regex.new(large)
    pre = re.literal_prefilter_for_spec.not_nil!
    pre.aho_for_spec?.should be_true
    re.is_accelerated.should be_false
    re.find("x" * 4096 + "needle02999").should eq(Regex::Automata::Match.must(0, 4096...4107))
    re.find(Regex::Automata::Input.new("needle02999").anchored(Regex::Automata::Anchored::Yes)).should eq(
      Regex::Automata::Match.must(0, 0...11)
    )
    patset = Regex::Automata::PatternSet.new(2)
    patset.insert(Regex::Automata::PatternID.new(1))
    re.which_overlapping_matches(Regex::Automata::Input.new("needle02999"), patset)
    patset.iter.to_a.should eq([Regex::Automata::PatternID.new(0), Regex::Automata::PatternID.new(1)])
  end

  it "never runs PikeVM after a direct literal hit or miss" do
    re = Regex::Automata::Meta::Regex.new("Sherlock")
    cache = re.create_cache
    slots = [nil, nil] of Int32?

    re.search_with(cache, Regex::Automata::Input.new("xxSherlock")).should eq(Regex::Automata::Match.must(0, 2...10))
    cache.pike_scratch_allocated_for_spec?.should be_false
    re.search_with(cache, Regex::Automata::Input.new("xxWatson")).should be_nil
    cache.pike_scratch_allocated_for_spec?.should be_false
    re.search_slots_with(cache, Regex::Automata::Input.new("xxWatson"), slots).should be_nil
    cache.pike_scratch_allocated_for_spec?.should be_false
  end
end
