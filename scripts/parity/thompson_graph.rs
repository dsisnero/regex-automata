use regex_automata::{
    nfa::thompson::{State, WhichCaptures, NFA},
    util::{primitives::PatternID, syntax},
};
use std::io::{self, BufRead};
fn unhex(text: &str) -> String {
    String::from_utf8(
        (0..text.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap())
            .collect(),
    )
    .unwrap()
}
fn snapshot(nfa: &NFA) -> String {
    let starts = (0..nfa.pattern_len())
        .map(|i| {
            nfa.start_pattern(PatternID::new(i).unwrap())
                .unwrap()
                .as_usize()
                .to_string()
        })
        .collect::<Vec<_>>()
        .join(",");
    let states = nfa
        .states()
        .iter()
        .map(|state| match state {
            State::ByteRange { trans } => {
                format!("B,{},{},{}", trans.start, trans.end, trans.next.as_usize())
            }
            State::Sparse(s) => format!(
                "S,{}",
                s.transitions
                    .iter()
                    .map(|t| format!("{}:{}:{}", t.start, t.end, t.next.as_usize()))
                    .collect::<Vec<_>>()
                    .join(",")
            ),
            State::Dense(_) => panic!("Unexpected dense state in Thompson compiler"),
            State::Look { look, next } => format!("L,{},{}", look.as_repr(), next.as_usize()),
            State::Union { alternates } => format!(
                "U,{}",
                alternates
                    .iter()
                    .map(|s| s.as_usize().to_string())
                    .collect::<Vec<_>>()
                    .join(",")
            ),
            State::BinaryUnion { alt1, alt2 } => {
                format!("Q,{},{}", alt1.as_usize(), alt2.as_usize())
            }
            State::Capture {
                next,
                pattern_id,
                group_index,
                slot,
            } => format!(
                "C,{},{},{},{}",
                next.as_usize(),
                pattern_id.as_usize(),
                group_index.as_usize(),
                slot.as_usize()
            ),
            State::Match { pattern_id } => format!("M,{}", pattern_id.as_usize()),
            State::Fail => "F".to_string(),
        })
        .collect::<Vec<_>>()
        .join("|");
    format!(
        "{};{};{};{};{};{};{}|{}",
        nfa.start_anchored().as_usize(),
        nfa.start_unanchored().as_usize(),
        starts,
        nfa.group_info().all_group_len(),
        nfa.is_utf8(),
        nfa.is_reverse(),
        nfa.has_empty(),
        states
    )
}
fn main() {
    // Normative syntax-wrapper contract behind the corrected Crystal assertion.
    let hir = syntax::parse_with(
        r"(?-u:[\xFF])",
        &syntax::Config::new().unicode(false).utf8(false),
    )
    .unwrap();
    match hir.kind() {
        regex_syntax::hir::HirKind::Literal(literal) => assert_eq!(&[255], literal.0.as_ref()),
        other => panic!("Expected singleton byte literal, got {other:?}"),
    }
    assert!(!hir.properties().is_utf8());
    for line in io::stdin().lock().lines() {
        let line = line.unwrap();
        let cols = line.split('\t').collect::<Vec<_>>();
        let opts = cols[1].split(',').collect::<Vec<_>>();
        let captures = match opts[0] {
            "none" => WhichCaptures::None,
            "implicit" => WhichCaptures::Implicit,
            "all" => WhichCaptures::All,
            _ => panic!(),
        };
        let mut compiler = NFA::compiler();
        compiler.configure(
            NFA::config()
                .which_captures(captures)
                .unanchored_prefix(opts[1] == "1")
                .reverse(opts[2] == "1")
                .shrink(opts[3] == "1")
                .utf8(opts[5] == "1"),
        );
        compiler.syntax(syntax::Config::new().utf8(opts[4] == "1"));
        let nfa = if cols[0].starts_with("direct_hir_") {
            use regex_syntax::hir::Hir;
            let literals = if cols[2] == "-" {
                vec![]
            } else {
                cols[2]
                    .split(',')
                    .map(|hex| {
                        let bytes = if hex == "_" {
                            vec![]
                        } else {
                            (0..hex.len())
                                .step_by(2)
                                .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
                                .collect()
                        };
                        Hir::literal(bytes)
                    })
                    .collect()
            };
            compiler
                .build_from_hir(&Hir::alternation(literals))
                .unwrap()
        } else if cols[0].starts_with("empty_class_") {
            use regex_syntax::hir::{Class, ClassBytes, ClassUnicode, Hir};
            let class = if cols[0] == "empty_class_bytes" {
                Class::Bytes(ClassBytes::empty())
            } else {
                Class::Unicode(ClassUnicode::empty())
            };
            compiler.build_from_hir(&Hir::class(class)).unwrap()
        } else {
            compiler
                .build_many(&cols[2].split(',').map(unhex).collect::<Vec<_>>())
                .unwrap()
        };
        println!("{}", snapshot(&nfa));
    }
}
