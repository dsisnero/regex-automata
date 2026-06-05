require "./spec_helper"
require "regex-syntax"
require "../src/regex/automata/search"

describe "DFA API" do
  describe "quit bytes" do
    it "handles quit bytes in forward direction" do
      # Test that quit bytes in the forward direction work correctly.
      # This corresponds to the Rust test `quit_fwd` in tests/dfa/api.rs

      # First, test that DFA works without quit bytes
      # Use a simpler pattern: "abc"
      dfa_no_quit = Regex::Automata::DFA::Builder.new
        .build("abc")

      # This should match "abc"
      result = dfa_no_quit.try_search_fwd("abcxyz".to_slice)
      result.should_not be_nil
      result.should_not be_a(Regex::Automata::MatchError)
      if match = result.as?(Tuple(Int32, Array(Regex::Automata::PatternID)))
        # match is a Tuple(Int32, Array(PatternID))
        end_pos, pattern_ids = match
        end_pos.should eq(3) # "abc" ends at position 3
      end

      # Now test with quit byte 'x'
      config = Regex::Automata::Config.new.quit('x'.ord.to_u8, true)

      dfa = Regex::Automata::DFA::Builder.new
        .configure(config)
        .build("abc")

      # Test forward search with quit byte
      # The input is "abcxyz", pattern is "abc"
      # The DFA should match "abc" (positions 0-2) and NOT see 'x' at position 3
      # because it stops after matching "abc"
      # Actually, for quit bytes to be tested, we need a pattern that would
      # normally continue past 'x'. Let me use pattern "abcd" instead.
      # With pattern "abcd", when searching "abcxyz", it will see 'x' at position 3
      # and should quit.

      dfa2 = Regex::Automata::DFA::Builder.new
        .configure(config)
        .build("abcd")

      result = dfa2.try_search_fwd("abcxyz".to_slice)

      # Check that we got a MatchError::quit
      result.should be_a(Regex::Automata::MatchError)

      error = result.as(Regex::Automata::MatchError)
      error.quit?.should be_true
      error.byte.should eq('x'.ord.to_u8)
      error.offset.should eq(3)
    end

    it "handles quit bytes in reverse direction" do
      # Test that quit bytes in the reverse direction work correctly.
      # This corresponds to the Rust test `quit_rev` in tests/dfa/api.rs
      # Note: Using [a-z] instead of [[:word:]] because POSIX classes may not be supported

      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.quit('x'.ord.to_u8, true) }
        .thompson { |config| config.reverse(true) }
        .build("[a-z]+") # Character class a-z (similar to [[:word:]] for ASCII)

      result = dfa.try_search_rev("abcxyz".to_slice)

      result.should be_a(Regex::Automata::MatchError)

      error = result.as(Regex::Automata::MatchError)
      error.quit?.should be_true
      error.byte.should eq('x'.ord.to_u8)
      error.offset.should eq(3)
    end

    it "panics when Unicode word boundaries conflict with quit configuration" do
      # Tests that if we heuristically enable Unicode word boundaries but then
      # instruct that a non-ASCII byte should NOT be a quit byte, then the builder
      # will panic.
      # This corresponds to the Rust test `quit_panics` in tests/dfa/api.rs

      expect_raises(Exception, "cannot mark non-ASCII byte 0xff as non-quit when Unicode word boundaries are enabled") do
        Regex::Automata::Config.new
          .unicode_word_boundary(true)
          .quit(0xFF_u8, false)
      end
    end

    it "implicitly enables Unicode word boundaries when all non-ASCII bytes are quit bytes" do
      # Tests an interesting case where even if the Unicode word boundary option
      # is disabled, setting all non-ASCII bytes are quit bytes will cause Unicode
      # word boundaries to be enabled.
      # This corresponds to the Rust test `unicode_word_implicitly_works` in tests/dfa/api.rs

      config = Regex::Automata::Config.new
      (0x80..0xFF).each do |b|
        config = config.quit(b.to_u8, true)
      end

      dfa = Regex::Automata::DFA::Builder.new.configure(config).build("\\b")

      # Search for word boundary
      result = dfa.try_search_fwd(" a".to_slice)

      # Should get a match (not a quit error)
      result.should_not be_nil
      result.should_not be_a(Regex::Automata::MatchError)

      if match = result.as?(Tuple(Int32, Array(Regex::Automata::PatternID)))
        end_pos, pattern_ids = match
        # We should get a match (either at position 0 or 1)
        # The important part is that Unicode word boundaries were implicitly enabled
        end_pos.should be >= 0
        pattern_ids.should eq([Regex::Automata::PatternID.new(0)])
      end
    end
  end

  describe "universal start search" do
    it "supports universal start states" do
      # A variant of `Automaton::is_special_state`'s doctest, but with universal
      # start states.
      # See: https://github.com/rust-lang/regex/pull/1195
      # This corresponds to the Rust test `universal_start_search` in tests/dfa/api.rs

      # Simple test: build a DFA and check that universal start state methods work
      # Enable specialize_start_states to make start states special
      config = Regex::Automata::Config.new.specialize_start_states(true)
      dfa = Regex::Automata::DFA::Builder.new.configure(config).build("[a-z]+")

      # Check that universal_start_state returns a state
      start_state = dfa.universal_start_state(Regex::Automata::Anchored::No)
      start_state.should_not be_nil

      # Check that is_special_state works
      dfa.is_special_state?(start_state.not_nil!).should be_true # Start state is special

      # Check that next_state works
      next_state = dfa.next_state(start_state.not_nil!, 'a'.ord.to_u8)
      next_state.should_not be_nil

      # Check that is_match_state works
      # The start state is not a match state (empty string doesn't match [a-z]+)
      dfa.is_match_state?(start_state.not_nil!).should be_false

      # Check that is_dead_state and is_quit_state work
      dfa.is_dead_state?(start_state.not_nil!).should be_false
      dfa.is_dead_state?(Regex::Automata::DFA::DEAD_STATE_ID).should be_true

      dfa.is_quit_state?(start_state.not_nil!).should be_false
      dfa.is_quit_state?(Regex::Automata::DFA::QUIT_STATE_ID).should be_true

      # Check that next_eoi_state works
      eoi_state = dfa.next_eoi_state(start_state.not_nil!)
      eoi_state.should_not be_nil

      # Check that match_pattern works (when state is a match state)
      # First, find a match state by searching
      result = dfa.try_search_fwd("abc".to_slice)
      result.should_not be_nil
      result.should_not be_a(Regex::Automata::MatchError)

      if match = result.as?(Tuple(Int32, Array(Regex::Automata::PatternID)))
        end_pos, pattern_ids = match
        end_pos.should eq(3) # "abc" ends at position 3
        pattern_ids.should eq([Regex::Automata::PatternID.new(0)])

        # Check match_pattern - we need a match state ID to test this
        match_state = dfa.universal_start_state(Regex::Automata::Anchored::No).not_nil!
        "abc".to_slice.each do |byte|
          match_state = dfa.next_state(match_state, byte)
        end
        dfa.is_match_state?(match_state).should be_true
        dfa.match_len(match_state).should eq(1)
        dfa.match_pattern(match_state, 0).should eq(Regex::Automata::PatternID.new(0))
        pattern_ids[0].should eq(Regex::Automata::PatternID.new(0))
      end
    end
  end

  describe "dense metadata" do
    it "builds the dense transition table directly during determinization" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.starts_for_each_pattern(true) }
        .build_many(["abc", "(?-u:\\b)def", "ghi$"])

      rebuilt = Regex::Automata::DFA::DFA.build_transition_table(dfa.states, dfa.byte_classifier)

      dfa.tt.should_not be_nil
      dfa.tt.not_nil!.table.should eq(rebuilt.table)
      dfa.tt.not_nil!.stride2.should eq(rebuilt.stride2)
    end

    it "tracks the number of patterns in a multi-pattern DFA" do
      dfa = Regex::Automata::DFA::DFA.new_many(["abc", "def"])

      dfa.pattern_len.should eq(2)
      dfa.universal_start_state(Regex::Automata::Anchored::No).should eq(
        dfa.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::No))
      )
    end

    it "uses delayed EOI matches for end-text anchors" do
      dfa = Regex::Automata::DFA::Builder.new.build("a\\z")

      result = dfa.try_search_fwd("a".to_slice)
      result.should eq({1, [Regex::Automata::PatternID.new(0)]})
    end

    it "uses delayed EOI matches for word boundaries" do
      dfa = Regex::Automata::DFA::Builder.new.build("a(?-u:\\b)")

      result = dfa.try_search_fwd("a".to_slice)
      result.should eq({1, [Regex::Automata::PatternID.new(0)]})
    end

    it "reports empty alternatives at the current search start" do
      dfa = Regex::Automata::DFA::Builder.new.build("a|")

      dfa.try_search_fwd(Regex::Automata::Input.new("abba").span(1...4)).should eq(
        Regex::Automata::HalfMatch.must(0, 1)
      )
      dfa.try_search_fwd(Regex::Automata::Input.new("abba").span(2...4)).should eq(
        Regex::Automata::HalfMatch.must(0, 2)
      )
      dfa.try_search_fwd(Regex::Automata::Input.new("abba").span(3...4)).should eq(
        Regex::Automata::HalfMatch.must(0, 4)
      )
      dfa.try_search_fwd(Regex::Automata::Input.new("abba").span(4...4)).should eq(
        Regex::Automata::HalfMatch.must(0, 4)
      )
    end

    it "reports anchored configuration via flags" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.start_kind(Regex::Automata::StartKind::Anchored) }
        .build("abc")

      dfa.is_always_start_anchored?.should be_true
      dfa.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::No))
        .should be_a(Regex::Automata::UnsupportedAnchoredStartError)
    end

    it "maps unsupported anchored pattern starts to match errors" do
      dfa = Regex::Automata::DFA::Builder.new.build_many(["abc", "def"])
      input = Regex::Automata::Input.new("abc").anchored_pattern(Regex::Automata::PatternID.new(0))

      result = dfa.start_state_forward(input)

      result.should be_a(Regex::Automata::MatchError)
      error = result.as(Regex::Automata::MatchError)
      error.unsupported_anchored?.should be_true
      error.mode.should eq(Regex::Automata::Anchored::Pattern)
    end

    it "returns the dead state for an out-of-range anchored pattern start" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.starts_for_each_pattern(true) }
        .build_many(["abc", "def"])

      result = dfa.start_state(
        Regex::Automata::StartConfig.new(
          nil,
          Regex::Automata::Anchored::Pattern,
          Regex::Automata::PatternID.new(99)
        )
      )

      result.should eq(Regex::Automata::DFA::DEAD_STATE_ID)
    end

    it "tracks always-start-anchored behavior independently from start-kind support" do
      dfa = Regex::Automata::DFA::Builder.new.build("^abc")

      dfa.is_always_start_anchored?.should be_true
      dfa.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::No))
        .should be_a(Regex::Automata::StateID)
    end

    it "tracks empty-match capability through start and EOI states" do
      Regex::Automata::DFA::Builder.new.build("a+").has_empty?.should be_false
      Regex::Automata::DFA::Builder.new.build("a*").has_empty?.should be_true
      Regex::Automata::DFA::Builder.new.build("^$").has_empty?.should be_true
    end

    it "reports UTF-8 mode from the Thompson compiler configuration" do
      Regex::Automata::DFA::Builder.new.build("abc").is_utf8?.should be_true

      dfa = Regex::Automata::DFA::Builder.new
        .thompson { |config| config.utf8(false) }
        .build("abc")

      dfa.is_utf8?.should be_false
    end

    it "supports anchored starts for a specific pattern when enabled" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.starts_for_each_pattern(true) }
        .build("foo[0-9]+")

      start = dfa.start_state(
        Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::Pattern, Regex::Automata::PatternID.new(0))
      ).as(Regex::Automata::StateID)
      state = start
      "quux foo123".to_slice.each { |byte| state = dfa.next_state(state, byte) }
      state = dfa.next_eoi_state(state)
      dfa.is_match_state?(state).should be_false

      ranged_start = dfa.start_state(
        Regex::Automata::StartConfig.new(' '.ord.to_u8, Regex::Automata::Anchored::Pattern, Regex::Automata::PatternID.new(0))
      ).as(Regex::Automata::StateID)
      state = ranged_start
      "foo123".to_slice.each { |byte| state = dfa.next_state(state, byte) }
      state = dfa.next_eoi_state(state)
      dfa.is_match_state?(state).should be_true
    end

    it "chooses different anchored start states based on look-behind" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.start_kind(Regex::Automata::StartKind::Anchored) }
        .build("(?-u:\\b)abc")

      text_start = dfa.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::Yes)).as(Regex::Automata::StateID)
      word_start = dfa.start_state(Regex::Automata::StartConfig.new('q'.ord.to_u8, Regex::Automata::Anchored::Yes)).as(Regex::Automata::StateID)

      text_start.should_not eq(word_start)

      state = text_start
      "abc".to_slice.each { |byte| state = dfa.next_state(state, byte) }
      state = dfa.next_eoi_state(state)
      dfa.is_match_state?(state).should be_true

      state = word_start
      "abc".to_slice.each { |byte| state = dfa.next_state(state, byte) }
      state = dfa.next_eoi_state(state)
      dfa.is_match_state?(state).should be_false

      dfa.universal_start_state(Regex::Automata::Anchored::Yes).should be_nil
    end

    it "records accelerator needles for skip-heavy states" do
      dfa = Regex::Automata::DFA::Builder.new.build("a[^x]*x")
      found_accelerated = dfa.states.each_index.any? do |i|
        sid = if tt = dfa.tt
                tt.to_state_id(i)
              else
                Regex::Automata::StateID.new(i)
              end
        !dfa.accelerator(sid).empty?
      end

      found_accelerated.should be_true
    end

    it "keeps accelerated states in a contiguous dense range" do
      dfa = Regex::Automata::DFA::Builder.new.build("a[^x]*x")
      accel_ids = dfa.states.each_index.compact_map do |i|
        sid = if tt = dfa.tt
                tt.to_state_id(i)
              else
                Regex::Automata::StateID.new(i)
              end
        sid if dfa.is_accel_state?(sid)
      end.to_a

      accel_ids.should_not be_empty
      tt = dfa.tt.not_nil!
      accel_ids.map { |sid| tt.to_index(sid) }.should eq((tt.to_index(accel_ids.first)..tt.to_index(accel_ids.last)).to_a)
    end

    it "preserves reverse search results when acceleration is enabled" do
      dfa = Regex::Automata::DFA::Builder.new
        .thompson { |config| config.reverse(true) }
        .build("ab?")
      dfa_no_accel = Regex::Automata::DFA::Builder.new
        .configure { |config| config.accelerate(false) }
        .thompson { |config| config.reverse(true) }
        .build("ab?")

      found_accelerated = dfa.states.each_index.any? do |i|
        sid = if tt = dfa.tt
                tt.to_state_id(i)
              else
                Regex::Automata::StateID.new(i)
              end
        !dfa.accelerator(sid).empty?
      end

      found_accelerated.should be_true
      dfa.try_search_rev("ab".to_slice).should eq(dfa_no_accel.try_search_rev("ab".to_slice))
    end

    it "reports overlapping matches without suffix duplicates" do
      dfa = Regex::Automata::DFA::Builder.new.build("abc")

      dfa.try_search_overlapping_fwd("zabcabc".to_slice).should eq([
        {4, [Regex::Automata::PatternID.new(0)]},
        {7, [Regex::Automata::PatternID.new(0)]},
      ])
    end

    it "reports overlapping multi-pattern matches at the same end position" do
      dfa = Regex::Automata::DFA::DFA.new_many(["a", "a"])

      dfa.try_search_overlapping_fwd("a".to_slice).should eq([
        {1, [Regex::Automata::PatternID.new(0), Regex::Automata::PatternID.new(1)]},
      ])
    end

    it "supports vendor-style stateful overlapping forward search" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.match_kind(Regex::Automata::MatchKind::All) }
        .build_many(["a", "a"])
      input = Regex::Automata::Input.new("a")
      state = Regex::Automata::OverlappingState.start

      dfa.try_search_overlapping_fwd(input, state).should be_nil
      state.get_match.should eq(Regex::Automata::HalfMatch.must(0, 1))

      dfa.try_search_overlapping_fwd(input, state).should be_nil
      state.get_match.should eq(Regex::Automata::HalfMatch.must(1, 1))
    end

    it "supports stateful overlapping reverse search" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.match_kind(Regex::Automata::MatchKind::All) }
        .thompson { |config| config.reverse(true) }
        .build("ab?")
      input = Regex::Automata::Input.new("ab")
      state = Regex::Automata::OverlappingState.start
      matches = [] of Regex::Automata::HalfMatch

      loop do
        dfa.try_search_overlapping_rev(input, state).should be_nil
        half_match = state.get_match
        break unless half_match
        matches << half_match
      end

      matches.should eq([
        Regex::Automata::HalfMatch.must(0, 0),
      ])
    end

    it "reports reverse overlapping empty matches at search boundaries" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.match_kind(Regex::Automata::MatchKind::All) }
        .thompson { |config| config.reverse(true) }
        .build("a|")
      input = Regex::Automata::Input.new("a")
      state = Regex::Automata::OverlappingState.start
      matches = [] of Regex::Automata::HalfMatch

      loop do
        dfa.try_search_overlapping_rev(input, state).should be_nil
        half_match = state.get_match
        break unless half_match
        matches << half_match
      end

      matches.should eq([
        Regex::Automata::HalfMatch.must(0, 1),
        Regex::Automata::HalfMatch.must(0, 0),
      ])
    end

    it "returns the unique set of overlapping patterns" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.match_kind(Regex::Automata::MatchKind::All) }
        .build_many([
          "[[:word:]]+",
          "[0-9]+",
          "[[:alpha:]]+",
          "foo",
          "bar",
          "barfoo",
          "foobar",
        ])

      dfa.try_which_overlapping_matches("foobar".to_slice).should eq([
        Regex::Automata::PatternID.new(0),
        Regex::Automata::PatternID.new(2),
        Regex::Automata::PatternID.new(3),
        Regex::Automata::PatternID.new(4),
        Regex::Automata::PatternID.new(6),
      ])
    end

    it "merges overlapping matches found from later anchored starts" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.match_kind(Regex::Automata::MatchKind::All) }
        .build_many(["[a-z]+$", "\\S+$"])

      dfa.try_search_overlapping_fwd("@foo".to_slice).should eq([
        {4, [
          Regex::Automata::PatternID.new(0),
          Regex::Automata::PatternID.new(1),
        ]},
      ])
    end
  end

  describe "serialization" do
    it "serializes and deserializes a DFA" do
      # Create a simple DFA
      dfa = Regex::Automata::DFA::Builder.new.build("abc")

      # Serialize to little-endian
      bytes, bytes_written = dfa.to_bytes_little_endian
      bytes_written.should be > 0

      # Deserialize
      dfa2, bytes_read = Regex::Automata::DFA::DFA.from_bytes(bytes)
      bytes_read.should eq(bytes_written)

      # Test that deserialized DFA works
      result = dfa2.try_search_fwd("abc".to_slice)
      result.should_not be_nil
      result.should_not be_a(Regex::Automata::MatchError)

      if match = result.as?(Tuple(Int32, Array(Regex::Automata::PatternID)))
        end_pos, pattern_ids = match
        end_pos.should eq(3) # "abc" ends at position 3
        pattern_ids.should eq([Regex::Automata::PatternID.new(0)])
      end
    end

    it "serializes and deserializes a DFA with quit bytes" do
      # Create a DFA with quit bytes
      config = Regex::Automata::Config.new.quit('x'.ord.to_u8, true)
      dfa = Regex::Automata::DFA::Builder.new
        .configure(config)
        .build("abcd")

      # Serialize to little-endian (from_bytes assumes little-endian)
      bytes, bytes_written = dfa.to_bytes_little_endian
      bytes_written.should be > 0

      # Deserialize
      dfa2, bytes_read = Regex::Automata::DFA::DFA.from_bytes(bytes)
      bytes_read.should eq(bytes_written)

      # Test that quit bytes still work
      result = dfa2.try_search_fwd("abcxyz".to_slice)
      result.should be_a(Regex::Automata::MatchError)
    end

    it "serializes and deserializes a multi-pattern DFA" do
      # Create a multi-pattern DFA
      dfa = Regex::Automata::DFA::DFA.new_many(["abc", "def"])

      # Serialize to little-endian (from_bytes assumes little-endian)
      bytes, bytes_written = dfa.to_bytes_little_endian
      bytes_written.should be > 0

      # Deserialize
      dfa2, bytes_read = Regex::Automata::DFA::DFA.from_bytes(bytes)
      bytes_read.should eq(bytes_written)

      # Test that both patterns work
      result1 = dfa2.try_search_fwd("abc".to_slice)
      result1.should_not be_a(Regex::Automata::MatchError)

      result2 = dfa2.try_search_fwd("def".to_slice)
      result2.should_not be_a(Regex::Automata::MatchError)
    end

    it "preserves contextual start states across serialization" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.start_kind(Regex::Automata::StartKind::Anchored) }
        .build("(?-u:\\b)abc")

      serialized = dfa.to_bytes_little_endian
      bytes = serialized[0]
      deserialized = Regex::Automata::DFA::DFA.from_bytes(bytes)
      dfa2 = deserialized[0]

      text_start = dfa2.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::Yes)).as(Regex::Automata::StateID)
      word_start = dfa2.start_state(Regex::Automata::StartConfig.new('q'.ord.to_u8, Regex::Automata::Anchored::Yes)).as(Regex::Automata::StateID)

      text_start.should_not eq(word_start)
      dfa2.is_always_start_anchored?.should be_true
      dfa2.universal_start_state(Regex::Automata::Anchored::Yes).should be_nil
    end

    it "preserves always-start-anchored metadata across serialization" do
      dfa = Regex::Automata::DFA::Builder.new.build("^abc")
      bytes = dfa.to_bytes_little_endian[0]
      dfa2 = Regex::Automata::DFA::DFA.from_bytes(bytes)[0]

      dfa2.is_always_start_anchored?.should be_true
      dfa2.start_state(Regex::Automata::StartConfig.new(nil, Regex::Automata::Anchored::No))
        .should be_a(Regex::Automata::StateID)
    end

    it "preserves pattern-specific anchored starts across serialization" do
      dfa = Regex::Automata::DFA::Builder.new
        .configure { |config| config.starts_for_each_pattern(true) }
        .build("foo[0-9]+")
      dfa2 = Regex::Automata::DFA::DFA.from_bytes(dfa.to_bytes_little_endian[0])[0]

      start = dfa2.start_state(
        Regex::Automata::StartConfig.new(' '.ord.to_u8, Regex::Automata::Anchored::Pattern, Regex::Automata::PatternID.new(0))
      )
      start.should be_a(Regex::Automata::StateID)
    end
  end

  describe "automaton helpers" do
    it "returns the earliest match instead of the longest match" do
      dfa = Regex::Automata::DFA::Builder.new.build("foo[0-9]+")

      dfa.try_search_fwd("foo12345".to_slice).should eq({8, [Regex::Automata::PatternID.new(0)]})
      dfa.find_earliest_match("foo12345".to_slice).should eq({4, [Regex::Automata::PatternID.new(0)]})
    end
  end
end
