require "./spec_helper"

# White-box assertion for Rust's private Strategy::new selector tests.
class Regex::Automata::Meta::Regex
  def literal_bypass_for_spec? : Bool
    !@literal_prefilter.nil? && !@literal_pattern_ids.nil?
  end

  def literal_prefilter_for_spec : ::Regex::Automata::Prefilter?
    @literal_prefilter
  end
end

class Regex::Automata::Prefilter
  def aho_for_spec? : Bool
    !@aho.nil?
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
    cache.raw_cache.setup_calls_for_spec.should eq(0)
    re.search_with(cache, Regex::Automata::Input.new("xxWatson")).should be_nil
    cache.raw_cache.setup_calls_for_spec.should eq(0)
    re.search_slots_with(cache, Regex::Automata::Input.new("xxWatson"), slots).should be_nil
    cache.raw_cache.setup_calls_for_spec.should eq(0)
  end
end
