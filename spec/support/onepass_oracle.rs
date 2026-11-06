// Generated admission/shape oracle for the pinned regex-automata 0.4.18.
use regex_automata::{
    dfa::onepass::DFA,
    nfa::thompson,
    util::{look::LookMatcher, syntax},
    MatchKind,
};
// The pinned Compiler derives Debug over its retained private Builder. For
// these two literal patterns the state list has no quoted delimiters, so a
// nesting-aware count observes the actual raw workspace without vendor edits.
fn retained_state_count(pattern: &str) -> usize {
    let compiler = thompson::NFA::compiler();
    compiler.build(pattern).unwrap();
    let debug = format!("{compiler:?}");
    let states = debug.split_once("states: [").unwrap().1;
    let mut nesting = 0;
    let mut count = 1;
    for ch in states.chars() {
        match ch {
            '[' | '{' | '(' => nesting += 1,
            ']' if nesting == 0 => return count,
            ']' | '}' | ')' => nesting -= 1,
            ',' if nesting == 0 => count += 1,
            _ => {}
        }
    }
    panic!("unterminated pinned compiler state list")
}

fn check_contracts() {
    assert_eq!(retained_state_count("a"), 7);
    assert_eq!(retained_state_count("^"), 5);
    let anchored = DFA::new(r"^\w+").unwrap();
    assert_eq!(anchored.state_len(), 318);
    assert_eq!(anchored.memory_usage(), 325636);
    use regex_automata::{Anchored, Input, Match, PatternID};
    assert_eq!(
        DFA::new(r"(?s-u:.)*?").unwrap_err().to_string(),
        "error building NFA"
    );
    assert!(DFA::builder()
        .configure(DFA::config().size_limit(Some(1)))
        .build("a*a")
        .unwrap_err()
        .to_string()
        .contains("exceeded size limit"));
    let re = DFA::new("(a)?b").unwrap();
    let mut cache = re.create_cache();
    let mut slots = vec![None; 4];
    assert_eq!(
        re.try_search_slots(
            &mut cache,
            &Input::new("ab").anchored(Anchored::Yes),
            &mut slots
        )
        .unwrap(),
        Some(PatternID::must(0))
    );
    assert_eq!(
        slots.iter().map(|s| s.map(|v| v.get())).collect::<Vec<_>>(),
        vec![Some(0), Some(2), Some(0), Some(1)]
    );
    assert_eq!(
        re.try_search_slots(
            &mut cache,
            &Input::new("b").anchored(Anchored::Yes),
            &mut slots
        )
        .unwrap(),
        Some(PatternID::must(0))
    );
    assert_eq!(
        slots.iter().map(|s| s.map(|v| v.get())).collect::<Vec<_>>(),
        vec![Some(0), Some(1), None, None]
    );
    let re = DFA::new("^a").unwrap();
    assert_eq!(
        re.try_search_slots(&mut re.create_cache(), &Input::new("a"), &mut [])
            .unwrap(),
        Some(PatternID::must(0))
    );
    let re = DFA::new("a").unwrap();
    let mut caps = re.create_captures();
    let mut cache = re.create_cache();
    re.captures(&mut cache, "a", &mut caps);
    assert!(re
        .try_search(&mut cache, &Input::new("a"), &mut caps)
        .is_err());
    assert_eq!(caps.pattern(), Some(PatternID::must(0)));
    assert!(re
        .try_search_slots(&mut re.create_cache(), &Input::new("a").span(1..0), &mut [])
        .unwrap()
        .is_none());
    let re = DFA::new(&"(a)".repeat(16)).unwrap();
    let mut slots = vec![None; 34];
    assert_eq!(
        re.try_search_slots(
            &mut re.create_cache(),
            &Input::new(&"a".repeat(16)).anchored(Anchored::Yes),
            &mut slots
        )
        .unwrap(),
        Some(PatternID::must(0))
    );
    assert_eq!(slots[33].unwrap().get(), 16);
    let mut builder = DFA::builder();
    builder.configure(DFA::config().match_kind(MatchKind::All));
    builder.thompson(thompson::Config::new().utf8(false));
    builder.thompson(thompson::Config::new().shrink(true));
    let mut copied = builder.clone();
    copied.configure(DFA::config().match_kind(MatchKind::LeftmostFirst));
    let original = builder.build("(a)+?").unwrap();
    let copy = copied.build("(a)+?").unwrap();
    assert!(!original.get_nfa().is_utf8());
    assert_eq!(
        original.find(&mut original.create_cache(), "aa"),
        Some(Match::must(0, 0..2))
    );
    assert_eq!(
        copy.find(&mut copy.create_cache(), "aa"),
        Some(Match::must(0, 0..1))
    );
    assert_eq!(
        original.clone().find(&mut original.create_cache(), "aa"),
        Some(Match::must(0, 0..2))
    );
}
fn main() {
    check_contracts();
    let mut tests = regex_test::RegexTests::new();
    for group in [
        "anchored",
        "bytes",
        "crazy",
        "crlf",
        "earliest",
        "empty",
        "expensive",
        "flags",
        "iter",
        "leftmost-all",
        "line-terminator",
        "misc",
        "multiline",
        "no-unicode",
        "overlapping",
        "regression",
        "set",
        "substring",
        "unicode",
        "utf8",
        "word-boundary",
        "word-boundary-special",
        "fowler/basic",
        "fowler/nullsubexpr",
        "fowler/repetition",
    ] {
        tests
            .load_slice(
                group,
                &std::fs::read(format!("vendor/regex/testdata/{group}.toml")).unwrap(),
            )
            .unwrap();
    }
    for mode in ["default", "no_byte_classes", "starts_for_each_pattern"] {
        for t in tests.iter() {
            let kind = match t.match_kind() {
                regex_test::MatchKind::LeftmostFirst => MatchKind::LeftmostFirst,
                regex_test::MatchKind::All => MatchKind::All,
                _ => continue,
            };
            if !t.anchored() {
                continue;
            }
            let mut look = LookMatcher::new();
            look.set_line_terminator(t.line_terminator());
            let result = DFA::builder()
                .configure(
                    DFA::config()
                        .match_kind(kind)
                        .byte_classes(mode != "no_byte_classes")
                        .starts_for_each_pattern(mode == "starts_for_each_pattern"),
                )
                .syntax(
                    syntax::Config::new()
                        .case_insensitive(t.case_insensitive())
                        .unicode(t.unicode())
                        .utf8(t.utf8())
                        .line_terminator(t.line_terminator()),
                )
                .thompson(thompson::Config::new().utf8(t.utf8()).look_matcher(look))
                .build_many(t.regexes());
            match result {
                Ok(re) => println!(
                    "{mode}\t{}\tok\t{}\t{}\t{}\t{}",
                    t.full_name(),
                    re.state_len(),
                    re.alphabet_len(),
                    re.stride(),
                    re.memory_usage()
                ),
                Err(e) => println!("{mode}\t{}\terr\t{e}", t.full_name()),
            }
        }
    }
}
