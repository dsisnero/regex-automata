use regex_automata::{
    dfa::{dense, onepass, Automaton},
    hybrid, meta,
    nfa::thompson::{self, backtrack, pikevm},
    util::{captures::Captures, look::LookMatcher, syntax},
    Anchored, HalfMatch, Input, MatchError, MatchErrorKind, MatchKind, PatternID,
};
use std::io::{self, BufRead};
fn unhex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}
fn mode(a: Anchored) -> String {
    match a {
        Anchored::No => "no".into(),
        Anchored::Yes => "yes".into(),
        Anchored::Pattern(p) => format!("p{}", p.as_usize()),
    }
}
fn error(e: MatchError) -> String {
    match e.kind() {
        MatchErrorKind::Quit { byte, offset } => format!("error:quit:{byte:02x}:{offset}"),
        MatchErrorKind::GaveUp { offset } => format!("error:gave-up:{offset}"),
        MatchErrorKind::UnsupportedAnchored { mode: a } => format!("error:anchor:{}", mode(*a)),
        MatchErrorKind::HaystackTooLong { len } => format!("error:long:{len}"),
        _ => panic!("unhandled {e}"),
    }
}
fn half(r: Result<Option<HalfMatch>, MatchError>) -> String {
    match r {
        Err(e) => error(e),
        Ok(None) => "none".into(),
        Ok(Some(m)) => format!("half:{}:{}", m.pattern().as_usize(), m.offset()),
    }
}
fn captures(r: Result<(), MatchError>, c: &Captures) -> String {
    if let Err(e) = r {
        return error(e);
    }
    let Some(p) = c.pattern() else {
        return "none".into();
    };
    let groups = c
        .iter()
        .map(|g| g.map_or("_".into(), |s| format!("{}-{}", s.start, s.end)))
        .collect::<Vec<_>>()
        .join(",");
    format!("caps:{}:{groups}", p.as_usize())
}
fn main() {
    for line in io::stdin().lock().lines() {
        let line = line.unwrap();
        let f: Vec<_> = line.split('\t').collect();
        let patterns: Vec<_> = f[1]
            .split(',')
            .map(|p| String::from_utf8(unhex(p)).unwrap())
            .collect();
        let hay = unhex(f[2]);
        let a = match f[5] {
            "no" => Anchored::No,
            "yes" => Anchored::Yes,
            s => Anchored::Pattern(PatternID::new(s[1..].parse().unwrap()).unwrap()),
        };
        let input = Input::new(&hay)
            .span(f[3].parse::<usize>().unwrap()..f[4].parse::<usize>().unwrap())
            .anchored(a)
            .earliest(f[6] == "1");
        let utf8 = f[7] == "1";
        let term = f[8].parse::<u8>().unwrap();
        let kind = if f[9] == "all" {
            MatchKind::All
        } else {
            MatchKind::LeftmostFirst
        };
        let syn = syntax::Config::new().utf8(utf8).line_terminator(term);
        let mut look = LookMatcher::new();
        look.set_line_terminator(term);
        let th = thompson::Config::new().utf8(utf8).look_matcher(look);
        for engine in [
            "dense",
            "dense-min",
            "sparse",
            "sparse-min",
            "hybrid",
            "pike",
            "backtrack",
            "onepass",
            "meta",
        ] {
            let output = match engine {
                "dense" | "dense-min" | "sparse" | "sparse-min" => {
                    let cfg = dense::Config::new()
                        .match_kind(kind)
                        .unicode_word_boundary(true)
                        .starts_for_each_pattern(true)
                        .minimize(engine.ends_with("min"));
                    match dense::Builder::new()
                        .configure(cfg)
                        .syntax(syn.clone())
                        .thompson(th.clone())
                        .build_many(&patterns)
                    {
                        Err(_) => "build-error".into(),
                        Ok(d) => {
                            if engine.starts_with("sparse") {
                                half(d.to_sparse().unwrap().try_search_fwd(&input))
                            } else {
                                half(d.try_search_fwd(&input))
                            }
                        }
                    }
                }
                "hybrid" => match hybrid::dfa::Builder::new()
                    .configure(
                        hybrid::dfa::Config::new()
                            .match_kind(kind)
                            .unicode_word_boundary(true)
                            .starts_for_each_pattern(true),
                    )
                    .syntax(syn.clone())
                    .thompson(th.clone())
                    .build_many(&patterns)
                {
                    Err(_) => "build-error".into(),
                    Ok(d) => half(d.try_search_fwd(&mut d.create_cache(), &input)),
                },
                "pike" => match pikevm::Builder::new()
                    .configure(pikevm::Config::new().match_kind(kind))
                    .syntax(syn.clone())
                    .thompson(th.clone())
                    .build_many(&patterns)
                {
                    Err(_) => "build-error".into(),
                    Ok(d) => {
                        let mut c = d.create_captures();
                        d.search(&mut d.create_cache(), &input, &mut c);
                        captures(Ok(()), &c)
                    }
                },
                "backtrack" => match backtrack::Builder::new()
                    .syntax(syn.clone())
                    .thompson(th.clone())
                    .build_many(&patterns)
                {
                    Err(_) => "build-error".into(),
                    Ok(d) => {
                        let mut c = d.create_captures();
                        let r = d.try_search(&mut d.create_cache(), &input, &mut c);
                        captures(r, &c)
                    }
                },
                "onepass" => match onepass::Builder::new()
                    .configure(
                        onepass::Config::new()
                            .match_kind(kind)
                            .starts_for_each_pattern(true),
                    )
                    .syntax(syn.clone())
                    .thompson(th.clone())
                    .build_many(&patterns)
                {
                    Err(_) => "build-error".into(),
                    Ok(d) => {
                        let mut c = d.create_captures();
                        let r = d.try_search(&mut d.create_cache(), &input, &mut c);
                        captures(r, &c)
                    }
                },
                "meta" => match meta::Builder::new()
                    .configure(
                        meta::Config::new()
                            .match_kind(kind)
                            .utf8_empty(utf8)
                            .line_terminator(term),
                    )
                    .syntax(syn.clone())
                    .build_many(&patterns)
                {
                    Err(_) => "build-error".into(),
                    Ok(d) => {
                        let mut c = d.create_captures();
                        d.search_captures(&input, &mut c);
                        captures(Ok(()), &c)
                    }
                },
                _ => unreachable!(),
            };
            println!("{}\t{engine}\t{output}", f[0]);
        }
    }
}
