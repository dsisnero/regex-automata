use regex_automata::{dfa::{dense, sparse, Automaton}, Input};
fn check(name: &str, dfa: &sparse::DFA<Vec<u8>>) {
    let base = format!("temp/sparse-wire-oracle/{name}");
    assert_eq!(dfa.to_bytes_little_endian(), std::fs::read(format!("{base}.le")).unwrap(), "{name}/LE");
    assert_eq!(dfa.to_bytes_big_endian(), std::fs::read(format!("{base}.be")).unwrap(), "{name}/BE");
    let expected = std::fs::read_to_string(format!("{base}.memory")).unwrap().parse::<usize>().unwrap();
    assert_eq!(dfa.memory_usage(), expected, "{name}/memory");
    println!("{name}: Rust conversion/endian/memory checks passed ({expected} bytes)");
}
fn main() {
    for name in std::fs::read_to_string("temp/sparse-wire-oracle/cases.txt").unwrap().lines() {
        let bytes = std::fs::read(format!("temp/sparse-wire-oracle/{name}.dense")).unwrap();
        let dense = dense::DFA::from_bytes(&bytes).unwrap().0;
        let dfa = dense.to_sparse().unwrap();
        for haystack in ["", "abc", "foo", "aZZx", "bar", "@foo aZZx"] {
            assert_eq!(dfa.try_search_fwd(&Input::new(haystack)), dense.try_search_fwd(&Input::new(haystack)), "{name}/{haystack}");
        }
        check(name, &dfa);
    }
    for name in ["sparse-fwd", "sparse-rev"] {
        let bytes = std::fs::read(format!("temp/sparse-wire-oracle/{name}.dfa")).unwrap();
        let (dfa, read) = sparse::DFA::from_bytes(&bytes).unwrap();
        assert_eq!(read, bytes.len());
        check(name, &dfa.to_owned());
    }
    // The upstream fuzz harness only asserts absence of panic. Check its
    // actual rejection result too, to justify Crystal's typed-error asserts.
    for suffix in [
        "a1b839d899ced76d5d7d0f78f9edb7a421505838",
        "dbb8172d3984e7e7d03f4b5f8bb86ecd1460eff9",
        "0da59c0434eaf35e5a6b470fa9244bb79c72b000",
        "61fd8e3003bf9d99f6c1e5a8488727eefd234b98",
        "c383ae07ec5e191422eadc492117439011816570",
        "d07703ceb94b10dcd9e4acb809f2051420449e2b",
        "18cfc246f2ddfc3dfc92b0c7893178c7cf65efa9",
    ] {
        let given = std::fs::read(format!("vendor/regex/regex-automata/tests/fuzz/testdata/deserialize_sparse_crash-{suffix}")).unwrap();
        let mut bytes = b"rust-regex-automata-dfa-sparse\0\0".to_vec();
        bytes.extend_from_slice(&0xFEFFu32.to_ne_bytes());
        bytes.extend_from_slice(&2u32.to_ne_bytes());
        bytes.extend_from_slice(&given[1 + usize::from(given[0])..]);
        assert!(sparse::DFA::from_bytes(&bytes).is_err(), "fuzz {suffix}");
    }
    println!("All seven pinned sparse fuzz payloads are rejected by Rust");
}
