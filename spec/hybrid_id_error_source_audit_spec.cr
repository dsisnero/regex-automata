require "./spec_helper"

# Direct port of the search loop in vendor hybrid/id.rs's LazyStateID doctest.
private def find_leftmost_first_from_id_doc(
  dfa : Regex::Automata::Hybrid::DFA,
  cache : Regex::Automata::Hybrid::Cache,
  haystack : Bytes,
) : Regex::Automata::HalfMatch? | Regex::Automata::MatchError
  sid = dfa.start_state_forward(cache, Regex::Automata::Input.new(haystack))
  return sid if sid.is_a?(Regex::Automata::MatchError)
  state = sid.as(Regex::Automata::Hybrid::LazyStateID)
  last_match = nil.as(Regex::Automata::HalfMatch?)

  haystack.each_with_index do |byte, index|
    next_state = dfa.next_state(cache, state, byte)
    return Regex::Automata::MatchError.gave_up(index) if next_state.is_a?(Regex::Automata::Hybrid::CacheError)
    state = next_state.as(Regex::Automata::Hybrid::LazyStateID)
    if state.is_tagged
      if state.is_match
        last_match = Regex::Automata::HalfMatch.new(dfa.match_pattern(cache, state, 0), index)
      elsif state.is_dead
        return last_match
      elsif state.is_quit
        return last_match unless last_match.nil?
        return Regex::Automata::MatchError.quit(byte, index)
      end
    end
  end

  next_state = dfa.next_eoi_state(cache, state)
  return Regex::Automata::MatchError.gave_up(haystack.size) if next_state.is_a?(Regex::Automata::Hybrid::CacheError)
  state = next_state.as(Regex::Automata::Hybrid::LazyStateID)
  if state.is_match
    last_match = Regex::Automata::HalfMatch.new(dfa.match_pattern(cache, state, 0), haystack.size)
  end
  last_match
end

describe "pinned Rust hybrid state ID and error contracts" do
  it "ports the low-level leftmost and EOI search examples from id.rs" do
    text = "123 foobar 4567".to_slice
    word = Regex::Automata::Hybrid::DFA.new("[a-z]+")
    digits = Regex::Automata::Hybrid::DFA.new("[0-9]{4}")
    multi = Regex::Automata::Hybrid::DFA.new_many(["[a-z]+", "[0-9]+"])

    find_leftmost_first_from_id_doc(word, word.create_cache, text).should eq(Regex::Automata::HalfMatch.must(0, 10))
    find_leftmost_first_from_id_doc(digits, digits.create_cache, text).should eq(Regex::Automata::HalfMatch.must(0, 15))
    cache = multi.create_cache
    find_leftmost_first_from_id_doc(multi, cache, text).should eq(Regex::Automata::HalfMatch.must(1, 3))
    find_leftmost_first_from_id_doc(multi, cache, text[3..]).should eq(Regex::Automata::HalfMatch.must(0, 7))
    find_leftmost_first_from_id_doc(multi, cache, text[10..]).should eq(Regex::Automata::HalfMatch.must(1, 5))
  end

  it "preserves the checked ID boundary, raw truncation, and independent tags" do
    max = Regex::Automata::Hybrid::LazyStateID::MAX
    Regex::Automata::Hybrid::LazyStateID.new(max).should eq(Regex::Automata::Hybrid::LazyStateID.new_unchecked(max))
    overflow = Regex::Automata::Hybrid::LazyStateID.new(max.to_u64 + 1_u64).as(Regex::Automata::Hybrid::LazyStateIDError)
    overflow.attempted.should eq(max.to_u64 + 1_u64)
    overflow.message.should eq("failed to create LazyStateID from #{max + 1}, which exceeds #{max}")
    Regex::Automata::Hybrid::LazyStateID.new_unchecked(UInt64::MAX).as_usize_unchecked.should eq(UInt32::MAX.to_u64)

    id = Regex::Automata::Hybrid::LazyStateID.new_unchecked(7)
    id.is_tagged.should be_false
    {id.to_unknown, id.to_dead, id.to_quit, id.to_start, id.to_match}.each do |tagged|
      tagged.is_tagged.should be_true
      tagged.as_usize_untagged.should eq(7_u64)
    end
    id.to_unknown.is_unknown.should be_true
    id.to_dead.is_dead.should be_true
    id.to_quit.is_quit.should be_true
    id.to_start.is_start.should be_true
    id.to_match.is_match.should be_true
  end

  it "exposes usize-width unsigned tagged and untagged ID views" do
    sid = Regex::Automata::Hybrid::LazyStateID.new_unchecked(7)
    tagged = sid.to_unknown

    sid.as_usize_untagged.should be_a(UInt64)
    tagged.as_usize_untagged.should eq(7_u64)
    tagged.as_usize_unchecked.should be_a(UInt64)
    tagged.as_usize_unchecked.should eq((1_u64 << 31) | 7_u64)
  end

  it "formats a double-quote quit byte with Rust ascii::escape_default" do
    Regex::Automata::Hybrid::StartError.quit('"'.ord.to_u8).message.should eq(
      "error computing start state because the look-behind byte \\\" triggered a quit state"
    )
  end

  it "exposes only the Rust-specified error sources" do
    nfa = Regex::Automata::NFA::BuildError.unsupported_captures
    Regex::Automata::Hybrid::BuildError.nfa(nfa).source.should be(nfa)
    Regex::Automata::Hybrid::BuildError.insufficient_cache_capacity(100_u64, 10_u64).source.should be_nil
    Regex::Automata::Hybrid::BuildError.insufficient_state_id_capacity(
      Regex::Automata::Hybrid::LazyStateIDError.new(Regex::Automata::Hybrid::LazyStateID::MAX.to_i64 + 1_i64)
    ).source.should be_nil

    cache = Regex::Automata::Hybrid::CacheError.bad_efficiency
    Regex::Automata::Hybrid::StartError.cache(cache).source.should be(cache)
    Regex::Automata::Hybrid::StartError.quit('x'.ord.to_u8).source.should be_nil
    Regex::Automata::Hybrid::StartError.unsupported_anchored(Regex::Automata::Anchored::Yes).source.should be_nil
  end

  it "matches the complete Rust hybrid error display variants" do
    Regex::Automata::Hybrid::BuildError.insufficient_cache_capacity(100_u64, 10_u64).message.should eq(
      "given cache capacity (10) is smaller than minimum required (100)"
    )
    Regex::Automata::Hybrid::BuildError.unsupported_dfa_word_boundary_unicode.message.should eq(
      "unsupported regex feature for DFAs: cannot build lazy DFAs for regexes with Unicode word boundaries; switch to ASCII word boundaries, or heuristically enable Unicode word boundaries or use a different regex engine"
    )
    Regex::Automata::Hybrid::StartError.cache.message.should eq("error computing start state because of cache inefficiency")
    Regex::Automata::Hybrid::StartError.unsupported_anchored(Regex::Automata::Anchored::Yes).message.should eq(
      "error computing start state because anchored searches are not supported or enabled"
    )
    Regex::Automata::Hybrid::StartError.unsupported_anchored(Regex::Automata::Anchored::No).message.should eq(
      "error computing start state because unanchored searches are not supported or enabled"
    )
    pattern = Regex::Automata::PatternID.new(2)
    Regex::Automata::Hybrid::StartError.unsupported_anchored(Regex::Automata::Anchored::Pattern, pattern).message.should eq(
      "error computing start state because anchored searches for a specific pattern (2) are not supported or enabled"
    )
    Regex::Automata::Hybrid::CacheError.too_many_cache_clears.message.should eq("lazy DFA cache has been cleared too many times")
    Regex::Automata::Hybrid::CacheError.bad_efficiency.message.should eq("lazy DFA cache has been cleared too many times")
  end
end
