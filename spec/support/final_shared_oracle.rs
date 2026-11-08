// Private-path edge cases exercised through the pinned public facade.
use regex_automata::util::interpolate;
fn main() {
    use regex_automata::{Input, MatchError};
    assert!(!Input::new(&[0x80, b'a']).is_char_boundary(0));
    assert!(Input::new(&[0x80, b'a']).is_char_boundary(1));
    assert_eq!(
        MatchError::quit(b'x', 7).to_string(),
        "quit search after observing byte x at offset 7"
    );
    assert_eq!(
        MatchError::quit(0xff, 0).to_string(),
        r"quit search after observing byte \xFF at offset 0"
    );
    use regex_automata::dfa::Automaton;
    for specialize in [false, true] {
        let dfa = regex_automata::dfa::dense::Builder::new()
            .configure(
                regex_automata::dfa::dense::Config::new()
                    .accelerate(false)
                    .specialize_start_states(specialize),
            )
            .build("abc")
            .unwrap();
        let start = dfa
            .start_state_forward(&regex_automata::Input::new("abc"))
            .unwrap();
        assert_eq!(dfa.is_start_state(start), specialize);
        for id in [
            regex_automata::util::primitives::StateID::new(1).unwrap(),
            regex_automata::util::primitives::StateID::MAX,
        ] {
            assert!(!dfa.is_dead_state(id));
            assert!(!dfa.is_quit_state(id));
            assert!(!dfa.is_match_state(id));
            assert!(!dfa.is_start_state(id));
            assert!(!dfa.is_accel_state(id));
        }
    }
    println!("Pinned specialized-only start-state classification passes");
    let vm = regex_automata::nfa::thompson::pikevm::PikeVM::new("").unwrap();
    let mut caps = vm.create_captures();
    caps.set_pattern(Some(regex_automata::PatternID::ZERO));
    caps.slots_mut()[0] = regex_automata::util::primitives::NonMaxUsize::new(0);
    caps.slots_mut()[1] = regex_automata::util::primitives::NonMaxUsize::new(1);
    let hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    if cfg!(debug_assertions) {
        use regex_automata::{hybrid, nfa::thompson};
        let forward = hybrid::dfa::DFA::new_many(&["a", "b"]).unwrap();
        let reverse = hybrid::dfa::DFA::builder()
            .thompson(thompson::Config::new().reverse(true))
            .build_many(&["b", "a"])
            .unwrap();
        let regex = hybrid::regex::Regex::builder().build_from_dfas(forward, reverse);
        let panic = std::panic::catch_unwind(|| {
            regex.try_search(&mut regex.create_cache(), &Input::new("za"))
        })
        .unwrap_err();
        assert!(panic
            .downcast_ref::<String>()
            .unwrap()
            .contains("forward and reverse search must match same pattern"));
    }
    assert!(std::panic::catch_unwind(|| caps.extract::<0>("é")).is_err());
    assert_eq!(caps.extract_bytes::<0>("é".as_bytes()).0, &[0xc3]);
    caps.slots_mut()[1] = regex_automata::util::primitives::NonMaxUsize::new(3);
    for panic in [
        std::panic::catch_unwind(|| {
            caps.extract::<1>("é");
        }),
        std::panic::catch_unwind(|| {
            caps.extract_bytes::<1>("é".as_bytes());
        }),
    ] {
        let error = panic.unwrap_err();
        let text = error
            .downcast_ref::<String>()
            .map(String::as_str)
            .or_else(|| error.downcast_ref::<&str>().copied())
            .unwrap();
        assert!(
            text.contains("bounds") || text.contains("out of range"),
            "{text}"
        );
    }
    std::panic::set_hook(hook);
    println!("Pinned extraction UTF-8/byte distinction and whole-match error order pass");
    for (replacement, expected) in [
        ("${+1}", "index:1"),
        ("${ 1}", "name: 1"),
        ("${1_0}", "name:1_0"),
        ("${-0}", "name:-0"),
        ("${18446744073709551615}", "index:18446744073709551615"),
        ("${18446744073709551616}", "name:18446744073709551616"),
    ] {
        let mut actual = String::new();
        interpolate::string(
            replacement,
            |i, dst| dst.push_str(&format!("index:{i}")),
            |name| {
                assert_eq!(expected, format!("name:{name}"));
                None
            },
            &mut actual,
        );
        if expected.starts_with("index:") {
            assert_eq!(actual, expected);
        } else {
            assert_eq!(actual, "");
        }
        let mut actual = Vec::new();
        interpolate::bytes(
            replacement.as_bytes(),
            |i, dst| dst.extend_from_slice(format!("index:{i}").as_bytes()),
            |name| {
                assert_eq!(expected, format!("name:{name}"));
                None
            },
            &mut actual,
        );
        if expected.starts_with("index:") {
            assert_eq!(actual, expected.as_bytes());
        } else {
            assert!(actual.is_empty());
        }
    }
    println!("Pinned interpolation numeric/name boundaries pass for strings and bytes");
}
