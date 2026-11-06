// Source-characterization checks beyond the pinned regex.rs doctests.
use regex_automata::{dfa::{dense, regex::Regex, Automaton, StartKind}, nfa::thompson, util::syntax, Input, Match, MatchKind};
fn main() {
    let mut builder = Regex::builder();
    builder.syntax(syntax::Config::new().case_insensitive(true));
    builder.thompson(thompson::Config::new().utf8(false));
    let re = builder.build("a").unwrap();
    assert!(re.is_match("A"));
    assert!(!re.forward().is_utf8());
    let mut copied = builder.clone();
    copied.syntax(syntax::Config::new().case_insensitive(false));
    assert!(builder.build("a").unwrap().is_match("A"));
    assert!(!copied.build("a").unwrap().is_match("A"));
    assert!(!copied.build("a").unwrap().forward().is_utf8());
    assert_eq!(re.clone().find("za"), Some(Match::must(0, 1..2)));
    let sparse = builder.build_sparse("a+").unwrap();
    assert_eq!(sparse.clone().find("zaaa"), Some(Match::must(0, 1..4)));
    let dfa = dense::Builder::new().configure(dense::Config::new().start_kind(StartKind::Anchored)).build("abc").unwrap();
    assert!(!dfa.is_always_start_anchored());
    assert!(dense::DFA::new(r"(?-u:\b\B)").unwrap().has_empty());
    for minimize in [false, true] {
        for accelerate in [false, true] {
            let mut builder = Regex::builder();
            builder.dense(dense::Config::new().minimize(minimize).accelerate(accelerate));
            let patterns = ["a", "a", r"(?-u:\b\B)"];
            let re = builder.build_many(&patterns).unwrap();
            assert_eq!(re.pattern_len(), 3);
            assert_eq!(re.find("a"), Some(Match::must(0, 0..1)));
            let re = builder.build_many_sparse(&patterns).unwrap();
            assert_eq!(re.pattern_len(), 3);
            assert_eq!(re.find("a"), Some(Match::must(0, 0..1)));
        }
    }
    let pattern = "(a)".repeat(100);
    let none = thompson::Config::new().which_captures(thompson::WhichCaptures::None);
    let fwd = thompson::NFA::compiler().configure(none.clone()).build(&pattern).unwrap();
    let rev = thompson::NFA::compiler().configure(none.reverse(true)).build(&pattern).unwrap();
    let limit = fwd.memory_usage().max(rev.memory_usage()) * 2;
    let re = Regex::builder().thompson(thompson::Config::new()
        .which_captures(thompson::WhichCaptures::All).nfa_size_limit(Some(limit)))
        .build(&pattern).unwrap();
    assert_eq!(re.find(&"a".repeat(100)), Some(Match::must(0, 0..100)));
    let re = Regex::new_many(&["ab", "b"]).unwrap();
    assert_eq!(re.find(Input::new("ab").earliest(true)), Some(Match::must(0, 0..2)));
    assert_eq!(Regex::new("a").unwrap().find(Input::new("za").range(1..2)), Some(Match::must(0, 1..2)));
    // Invalid pairs have unspecified search behavior, but preserve the exact
    // explicit invariant assertions in the pinned source.
    let old_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let missing = Regex::builder().build_from_dfas(dense::DFA::new("a").unwrap(), dense::DFA::never_match().unwrap());
    assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| missing.try_search(&Input::new("a")))).is_err());
    let reverse = dense::Builder::new().configure(dense::Config::new().start_kind(StartKind::Anchored).match_kind(MatchKind::All))
        .thompson(thompson::Config::new().reverse(true)).build_many(&["z", "a"]).unwrap();
    let mismatch = Regex::builder().build_from_dfas(dense::DFA::new("a").unwrap(), reverse);
    let mismatch_panics = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| mismatch.try_search(&Input::new("a")))).is_err();
    std::panic::set_hook(old_hook);
    assert!(mismatch_panics);
    println!("Pinned Rust wrapper flags, builder mutation, capture suppression, pattern counts, Input/earliest and invariants pass");
}
