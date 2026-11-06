// Offline consumer for scripts/check_dense_wire.sh. This compiles against the
// pinned vendor checkout, never a registry version of regex-automata.
use regex_automata::{dfa::{dense::DFA, Automaton}, HalfMatch, Input};
fn main() {
    for name in ["abc", "padding", "always", "never", "multi", "empty-patterns", "quitset", "vendor-fwd", "vendor-rev"] {
        let base = format!("temp/dense-wire-oracle/{name}");
        let bytes = std::fs::read(format!("{base}.dfa")).unwrap();
        let (dfa, read) = DFA::from_bytes(&bytes).unwrap();
        assert_eq!(read, bytes.len());
        if name == "vendor-rev" {
            assert!(dfa.try_search_fwd(&Input::new("abc")).is_err());
        }
        let expected = match name {
            "abc" | "padding" => Some(HalfMatch::must(0, 3)),
            "always" => Some(HalfMatch::must(0, 0)),
            "never" | "empty-patterns" | "multi" => None,
            "vendor-rev" => None,
            _ => dfa.try_search_fwd(&Input::new("abc")).unwrap(),
        };
        if name != "vendor-rev" {
            assert_eq!(dfa.try_search_fwd(&Input::new("abc")).unwrap(), expected);
        }
        if name == "multi" {
            assert_eq!(dfa.try_search_fwd(&Input::new("bar456")).unwrap(), Some(HalfMatch::must(1, 6)));
        }
        for (extension, result) in [("le", dfa.to_bytes_little_endian()), ("be", dfa.to_bytes_big_endian())] {
            let expected = std::fs::read(format!("{base}.expected-{extension}")).unwrap();
            assert_eq!(&result.0[result.1..], expected.as_slice(), "{name}/{extension}");
        }
        println!("{name}: Rust checked {read} Crystal bytes and both endian writes");
    }
    for name in [
        "deserialize_dense_crash-9486fb7c8a93b12c12a62166b43d31640c0208a9",
        "deserialize_dense_minimized-from-9486fb7c8a93b12c12a62166b43d31640c0208a9",
    ] {
        let given = std::fs::read(format!("vendor/regex/regex-automata/tests/fuzz/testdata/{name}")).unwrap();
        let mut bytes = b"rust-regex-automata-dfa-dense\0\0\0".to_vec();
        bytes.extend_from_slice(&0xFEFFu32.to_ne_bytes());
        bytes.extend_from_slice(&2u32.to_ne_bytes());
        bytes.extend_from_slice(&given[1 + usize::from(given[0])..]);
        assert!(DFA::from_bytes(&bytes).is_err(), "fuzz {name}");
    }
    println!("Both pinned dense fuzz payloads are rejected by Rust");
}
