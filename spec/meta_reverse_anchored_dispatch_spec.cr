require "./spec_helper"

# Rust's ReverseAnchored strategy returns a clean reverse miss directly;
# it only invokes Core's no-fail path when the reverse engine reports an error.
class Regex::Automata::Meta::Regex
  def reverse_anchored_selected_for_spec? : Bool
    !@reverse_anchored_dfa.nil? || !@reverse_anchored_hybrid.nil?
  end

  def force_nofail_core_for_reverse_spec : Nil
    @core_dfa = nil
    @core_hybrid = nil
    @core_onepass = nil
    @core_backtrack = nil
  end

  def reverse_dense_for_spec : ::Regex::Automata::DFA::DFA?
    @reverse_anchored_dfa
  end
end

describe "pinned Rust ReverseAnchored dispatch" do
  it "ends a clean reverse miss without trying Core" do
    re = Regex::Automata::Meta::Regex.new("foo$")
    cache = re.create_cache
    re.reverse_anchored_selected_for_spec?.should be_true
    re.force_nofail_core_for_reverse_spec
    re.search_with(cache, Regex::Automata::Input.new("xxbar")).should be_nil
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "returns a half-match miss without retrying Core" do
    re = Regex::Automata::Meta::Regex.new("foo$")
    cache = re.create_cache
    re.reverse_anchored_selected_for_spec?.should be_true
    re.force_nofail_core_for_reverse_spec
    re.search_half_with(cache, Regex::Automata::Input.new("xxbar")).should be_nil
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "also ends a clean hybrid reverse miss without Core work" do
    re = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.dfa(false))
      .build("\\w+Holmes$")
    cache = re.create_cache
    re.reverse_anchored_selected_for_spec?.should be_true
    re.reverse_dense_for_spec.should be_nil
    re.force_nofail_core_for_reverse_spec
    re.search_with(cache, Regex::Automata::Input.new("xxWatson")).should be_nil
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "falls back to Core for an explicitly anchored input" do
    re = Regex::Automata::Meta::Regex.new("foo$")
    cache = re.create_cache
    re.reverse_anchored_selected_for_spec?.should be_true
    re.force_nofail_core_for_reverse_spec
    re.search_with(cache, Regex::Automata::Input.new("foo").anchored(Regex::Automata::Anchored::Yes))
      .should eq(Regex::Automata::Match.must(0, 0...3))
    cache.pike_scratch_allocated_for_spec?.should be_true
  end

  it "still matches when reverse DFA quits on a Unicode word boundary" do
    re = Regex::Automata::Meta::Regex.new("\\bélan$")
    re.reverse_anchored_selected_for_spec?.should be_true
    re.reverse_dense_for_spec.not_nil!.try_search_rev("élan".to_slice)
      .should be_a(Regex::Automata::MatchError)
    cache = re.create_cache
    input = Regex::Automata::Input.new("élan")
    re.search_with(cache, input).should eq(Regex::Automata::Match.must(0, 0...5))
    re.search_half_with(cache, input).should eq(Regex::Automata::HalfMatch.must(0, 5))
    re.is_match_with(cache, input).should be_true
    caps = re.create_captures
    re.search_captures_with(cache, input, caps)
    caps.get_match.should eq(Regex::Automata::Match.must(0, 0...5))
    slots = [nil, nil] of Int32?
    re.search_slots_with(cache, input, slots).should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 5])
  end

  it "clears capture and slot results on a clean reverse miss without Core scratch" do
    re = Regex::Automata::Meta::Regex.new("(foo)$")
    cache = re.create_cache
    re.reverse_anchored_selected_for_spec?.should be_true
    re.force_nofail_core_for_reverse_spec
    caps = re.create_captures
    slots = [0, 3, 0, 3] of Int32?
    re.search_captures_with(cache, Regex::Automata::Input.new("xxbar"), caps)
    caps.get_match.should be_nil
    re.search_slots_with(cache, Regex::Automata::Input.new("xxbar"), slots).should be_nil
    slots.should eq([nil, nil, nil, nil])
    cache.pike_scratch_allocated_for_spec?.should be_false
  end

  it "delegates overlapping pattern discovery to Core" do
    re = Regex::Automata::Meta::Regex.new_many(["foo$", "bar$"])
    re.reverse_anchored_selected_for_spec?.should be_true
    matches = Regex::Automata::PatternSet.new(2)
    re.which_overlapping_matches_with(re.create_cache, Regex::Automata::Input.new("xxbar"), matches)
    matches.iter.to_a.should eq([Regex::Automata::PatternID.new(1)])
  end
end
