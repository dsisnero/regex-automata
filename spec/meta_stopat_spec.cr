require "./spec_helper"

private def build_forward_meta_dfa(
  pattern : String,
  config : Regex::Automata::DFA::Config = Regex::Automata::DFA::DFA.config,
) : Regex::Automata::DFA::DFA
  Regex::Automata::DFA::Builder.new
    .thompson do |thompson|
      thompson
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
    .build(pattern)
end

describe Regex::Automata::Meta::StopAt do
  it "reports the point where an anchored forward search becomes dead" do
    dfa = build_forward_meta_dfa("foo")
    input = Regex::Automata::Input.new("bar")
      .span(0...3)
      .anchored(Regex::Automata::Anchored::Yes)

    Regex::Automata::Meta::StopAt.dfa_try_search_half_fwd(dfa, input).should eq(0)
  end

  it "reports an end-of-input match at the complete haystack length" do
    dfa = build_forward_meta_dfa("foo$")
    input = Regex::Automata::Input.new("foo")
      .span(0...3)
      .anchored(Regex::Automata::Anchored::Yes)

    Regex::Automata::Meta::StopAt.dfa_try_search_half_fwd(dfa, input).should eq(
      Regex::Automata::HalfMatch.must(0, 3)
    )
  end

  it "preserves the byte offset when the forward DFA quits" do
    config = Regex::Automata::DFA::DFA.config.quit('x'.ord.to_u8, true)
    dfa = build_forward_meta_dfa("foo", config)
    input = Regex::Automata::Input.new("xfoo")
      .span(0...4)
      .anchored(Regex::Automata::Anchored::Yes)

    result = Regex::Automata::Meta::StopAt.dfa_try_search_half_fwd(dfa, input)
    result.should be_a(Regex::Automata::Meta::RetryFailError)
    result.as(Regex::Automata::Meta::RetryFailError).offset.should eq(0)
  end
end
