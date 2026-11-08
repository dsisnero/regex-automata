use regex_automata::{
    dfa::{dense, Automaton},
    meta,
    nfa::thompson,
    util::prefilter::Prefilter,
    Input, MatchKind, Span,
};
use std::time::{Duration, Instant};
fn measure(name: &str, expected: u64, mut operation: impl FnMut() -> u64) {
    assert_eq!(operation(), expected, "{name}");
    if std::env::args().any(|a| a == "--check") {
        println!("{name}\t{expected}");
        return;
    }
    let duration = Duration::from_millis(
        std::env::var("BENCH_MS")
            .unwrap_or("150".into())
            .parse()
            .unwrap(),
    );
    let samples = std::env::var("BENCH_SAMPLES")
        .unwrap_or("5".into())
        .parse::<usize>()
        .unwrap();
    assert!(duration > Duration::ZERO && samples >= 4);
    for sample in 0..samples {
        let started = Instant::now();
        let mut iterations = 0u64;
        let mut checksum = 0u64;
        loop {
            for _ in 0..16 {
                checksum = checksum.wrapping_add(std::hint::black_box(operation()));
            }
            iterations += 16;
            if started.elapsed() >= duration {
                break;
            }
        }
        let elapsed = started.elapsed().as_nanos();
        assert_eq!(checksum, expected.wrapping_mul(iterations));
        println!("{name}\t{sample}\t{iterations}\t{elapsed}\t-\t-\t{checksum}");
    }
}
fn main() {
    let size = std::env::var("BENCH_SIZE")
        .unwrap_or("65536".into())
        .parse::<usize>()
        .unwrap();
    assert!(size >= 256);
    for count in 1..=3 {
        let needles = &["x", "y", "z"][..count];
        let pre = Prefilter::new(MatchKind::LeftmostFirst, needles).unwrap();
        for hit in [false, true] {
            let hay = format!(
                "{}{}",
                "a".repeat(size),
                if hit { needles[count - 1] } else { "a" }
            )
            .into_bytes();
            let span = Span::from(0..hay.len());
            measure(
                &format!("byte{count}-{}", if hit { "hit" } else { "miss" }),
                if hit { hay.len() as u64 } else { 0 },
                || pre.find(&hay, span).map_or(0, |s| s.end as u64),
            );
        }
    }
    for (label, needle) in [
        ("short", "rareXYZ".into()),
        ("long", format!("{}b", "a".repeat(127))),
        ("periodic", format!("{}ac", "ab".repeat(63))),
    ] {
        let pre = Prefilter::new(MatchKind::LeftmostFirst, &[needle.as_str()]).unwrap();
        for hit in [false, true] {
            let prefix = if label == "periodic" {
                "ab".repeat(size / 2)
            } else {
                "a".repeat(size)
            };
            let hay = format!("{prefix}{}", if hit { &needle } else { "" }).into_bytes();
            let span = Span::from(0..hay.len());
            measure(
                &format!("memmem-{label}-{}", if hit { "hit" } else { "miss" }),
                if hit { hay.len() as u64 } else { 0 },
                || pre.find(&hay, span).map_or(0, |s| s.end as u64),
            );
        }
    }
    for count in [2, 16, 65] {
        let needles = (0..count)
            .map(|i| format!("key{i:03}Z"))
            .collect::<Vec<_>>();
        let pre = Prefilter::new(MatchKind::LeftmostFirst, &needles).unwrap();
        let hay = format!("{}{}", "a".repeat(size), needles.last().unwrap()).into_bytes();
        let span = Span::from(0..hay.len());
        measure(&format!("teddy{count}"), hay.len() as u64, || {
            pre.find(&hay, span).map_or(0, |s| s.end as u64)
        });
    }
    let re = meta::Regex::new("[a-z]+[0-9]+").unwrap();
    let input = Input::new("abc123");
    let mut cache = re.create_cache();
    measure("meta-pool", 6, || {
        re.search_half(&input).map_or(0, |m| m.offset() as u64)
    });
    measure("meta-cache", 6, || {
        re.search_half_with(&mut cache, &input)
            .map_or(0, |m| m.offset() as u64)
    });
    let dfa = dense::Builder::new()
        .configure(dense::Config::new().accelerate(false))
        .build("[a-z]+Z")
        .unwrap();
    let hay = format!("{}Z", "a".repeat(size));
    let input = Input::new(&hay);
    measure("dense-scalar-loop", hay.len() as u64, || {
        dfa.try_search_fwd(&input)
            .unwrap()
            .map_or(0, |m| m.offset() as u64)
    });
    let reverse = dense::Builder::new()
        .configure(dense::Config::new().accelerate(false))
        .thompson(thompson::Config::new().reverse(true))
        .build("[a-z]+Z")
        .unwrap();
    measure("dense-reverse-loop", 1, || {
        reverse
            .try_search_rev(&input)
            .unwrap()
            .map_or(0, |m| m.offset() as u64 + 1)
    });
    let nfa = thompson::NFA::new("(?:(?:ab|ac|ad)+[0-9]{1,4}|(?:foo|bar|baz)+x)").unwrap();
    measure("dense-build", 1, || {
        dense::Builder::new()
            .build_from_nfa(&nfa)
            .unwrap()
            .pattern_len() as u64
    });
}
