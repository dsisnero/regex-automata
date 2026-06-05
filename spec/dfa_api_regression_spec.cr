require "./spec_helper"

describe "DFA API regressions" do
  it "reports forward quit bytes for standard and overlapping searches" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::Config.new.quit('x'.ord.to_u8, true))
      .build("[[:word:]]+$")

    dfa.try_search_fwd(Regex::Automata::Input.new("abcxyz")).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 3)
    )

    state = Regex::Automata::OverlappingState.start
    dfa.try_search_overlapping_fwd(Regex::Automata::Input.new("abcxyz"), state).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 3)
    )
  end

  it "reports reverse quit bytes" do
    dfa = Regex::Automata::DFA::Builder.new
      .configure(Regex::Automata::Config.new.quit('x'.ord.to_u8, true))
      .thompson { |config| config.reverse(true) }
      .build("^[[:word:]]+")

    dfa.try_search_rev(Regex::Automata::Input.new("abcxyz")).should eq(
      Regex::Automata::MatchError.quit('x'.ord.to_u8, 3)
    )
  end

  it "rejects conflicting non-ASCII quit-byte configuration when Unicode boundaries are enabled" do
    expect_raises(Exception, "cannot mark non-ASCII byte 0xff as non-quit when Unicode word boundaries are enabled") do
      Regex::Automata::Config.new
        .unicode_word_boundary(true)
        .quit(0xFF_u8, false)
    end
  end

  it "implicitly enables Unicode word boundaries when all non-ASCII bytes are quit bytes" do
    config = Regex::Automata::Config.new
    (0x80..0xFF).each do |byte|
      config.quit(byte.to_u8, true)
    end

    dfa = Regex::Automata::DFA::Builder.new.configure(config).build("\\b")

    dfa.try_search_fwd(Regex::Automata::Input.new(" a")).should eq(
      Regex::Automata::HalfMatch.must(0, 1)
    )
  end

  it "supports manual search via universal start states" do
    check = ->(automaton : Regex::Automata::Automaton, haystack : String, expected_offset : Int32) do
      state = automaton.universal_start_state(Regex::Automata::Anchored::No)
      state.should_not be_nil

      current = state.not_nil!
      last_match : Regex::Automata::HalfMatch? = nil

      haystack.to_slice.each_with_index do |byte, i|
        current = automaton.next_state(current, byte)
        next unless automaton.is_special_state?(current)

        if automaton.is_match_state?(current)
          last_match = Regex::Automata::HalfMatch.new(automaton.match_pattern(current, 0), i)
        elsif automaton.is_dead_state?(current)
          break
        elsif automaton.is_quit_state?(current)
          break if last_match
          raise "unexpected quit state at #{i}"
        end
      end

      current = automaton.next_eoi_state(current)
      if automaton.is_match_state?(current)
        last_match = Regex::Automata::HalfMatch.new(
          automaton.match_pattern(current, 0),
          haystack.bytesize
        )
      end

      last_match.should_not be_nil
      last_match.not_nil!.should eq(Regex::Automata::HalfMatch.must(0, expected_offset))
    end

    dfa = Regex::Automata::DFA::Builder.new.build("[a-z]+")
    check.call(dfa, "123 foobar 4567", 10)
  end
end
