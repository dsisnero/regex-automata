require "./spec_helper"

private def build_forward_meta_dfa(pattern : String) : Regex::Automata::DFA::DFA
  builder = Regex::Automata::DFA::Builder.new
    .thompson do |config|
      config
        .which_captures(Regex::Automata::NFA::WhichCaptures::None)
        .unanchored_prefix(false)
    end
    .configure(
      Regex::Automata::DFA::DFA.config
        .match_kind(Regex::Automata::MatchKind::All)
        .prefilter(nil)
        .accelerate(false)
        .start_kind(Regex::Automata::StartKind::Anchored)
        .starts_for_each_pattern(false)
        .specialize_start_states(false)
    )
  builder.build(pattern)
end

describe Regex::Automata::Meta::StopAt do
  it "returns the stop offset when a forward anchored search fails late" do
    dfa = build_forward_meta_dfa("\\d+XYZ\\d+")
    input = Regex::Automata::Input.new("123XYZabc")
      .span(0...9)
      .anchored(Regex::Automata::Anchored::Yes)

    Regex::Automata::Meta::StopAt.dfa_try_search_half_fwd(dfa, input).should eq(6)
  end

  it "returns a half match when a forward anchored search succeeds" do
    dfa = build_forward_meta_dfa("\\d+XYZ\\d+")
    input = Regex::Automata::Input.new("123XYZ456")
      .span(0...9)
      .anchored(Regex::Automata::Anchored::Yes)

    Regex::Automata::Meta::StopAt.dfa_try_search_half_fwd(dfa, input).should eq(
      Regex::Automata::HalfMatch.must(0, 9)
    )
  end
end
