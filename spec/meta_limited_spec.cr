require "./spec_helper"

private def build_reverse_meta_dfa(
  pattern : String,
  config : Regex::Automata::DFA::Config = Regex::Automata::DFA::DFA.config,
) : Regex::Automata::DFA::DFA
  builder = Regex::Automata::DFA::Builder.new
    .thompson do |config|
      config
        .reverse(true)
        .which_captures(Regex::Automata::NFA::WhichCaptures::None)
        .unanchored_prefix(false)
    end
    .configure(
      config
        .match_kind(Regex::Automata::MatchKind::All)
        .prefilter(nil)
        .accelerate(false)
        .start_kind(Regex::Automata::StartKind::Anchored)
        .starts_for_each_pattern(false)
        .specialize_start_states(false)
    )
  builder.build(pattern)
end

describe Regex::Automata::Meta::Limited do
  it "rejects truncated reverse starts that could be false positives" do
    dfa = build_reverse_meta_dfa("[0-9]*foo")
    input = Regex::Automata::Input.new("x123foo")
      .span(0...7)
      .anchored(Regex::Automata::Anchored::Yes)

    result = Regex::Automata::Meta::Limited.dfa_try_search_half_rev(dfa, input, 0)
    result.should be_a(Regex::Automata::Meta::RetryQuadraticError)
  end

  it "returns a real bounded reverse start when the match is provable" do
    dfa = build_reverse_meta_dfa("[0-9]+foo")
    input = Regex::Automata::Input.new("123foo")
      .span(0...6)
      .anchored(Regex::Automata::Anchored::Yes)

    Regex::Automata::Meta::Limited.dfa_try_search_half_rev(dfa, input, 0).should eq(
      Regex::Automata::HalfMatch.must(0, 0)
    )
  end

  it "retries when the reverse search would pass its minimum start" do
    dfa = build_reverse_meta_dfa("foo")
    input = Regex::Automata::Input.new("foo")
      .span(0...3)
      .anchored(Regex::Automata::Anchored::Yes)

    result = Regex::Automata::Meta::Limited.dfa_try_search_half_rev(dfa, input, 2)
    result.should be_a(Regex::Automata::Meta::RetryQuadraticError)
  end

  it "preserves the byte offset when a reverse DFA quits" do
    config = Regex::Automata::DFA::DFA.config.quit('x'.ord.to_u8, true)
    dfa = build_reverse_meta_dfa("foo", config)
    input = Regex::Automata::Input.new("foox")
      .span(0...4)
      .anchored(Regex::Automata::Anchored::Yes)

    result = Regex::Automata::Meta::Limited.dfa_try_search_half_rev(dfa, input, 0)
    result.should be_a(Regex::Automata::Meta::RetryFailError)
    result.as(Regex::Automata::Meta::RetryFailError).offset.should eq(3)
  end
end
