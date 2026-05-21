# Parity Plan

## Current Focus

- [ ] Dense DFA — build and configuration
  - Upstream scope: `src/dfa/dense.rs`, `src/dfa/accel.rs`, `src/dfa/start.rs`, `src/dfa/special.rs`
  - Inventory ids: `src/dfa/dense.rs::*`, `src/dfa/accel.rs::*`, `src/dfa/start.rs::*`, `src/dfa/special.rs::*`
  - Red: port config/build/start-state specs before broadening search behavior
  - Green: `src/regex/automata/dfa.cr`, `src/regex/automata/accel.cr`, `src/regex/automata/special.cr`, `src/regex/automata/start_config.cr`, `src/regex/automata/start_table.cr`
  - Done when: dense DFA builder/config/start-state parity specs are green and the covered rows are `ported`

- [ ] Dense DFA — search and overlapping search
  - Upstream scope: search paths in `src/dfa/dense.rs` and `src/dfa/automaton.rs`
  - Inventory ids: `src/dfa/dense.rs::*`, `src/dfa/automaton.rs::*`
  - Red: port forward, reverse, earliest, and overlapping-search DFA specs
  - Green: `src/regex/automata/dfa.cr`, `src/regex/automata/automaton.cr`, `src/regex/automata/dfa_regex.cr`
  - Progress: full-`Input` ranged forward context and delayed-match state construction now follow the vendor search model for current-search-start empty alternatives; broader overlapping and remaining helper parity still need direct coverage
  - Done when: dense DFA search semantics match upstream on the ported parity suite

- [ ] Dense DFA — regex convenience wrapper parity
  - Upstream scope: `src/dfa/regex.rs`, plus iterator behavior from `src/util/iter.rs`
  - Inventory ids: `src/dfa/regex.rs::*`
  - Red: port empty-match iteration, UTF-8 iteration, always-anchored, and builder-validation parity specs before adding more surface area
  - Green: `src/regex/automata/dfa_regex.cr`, `src/regex/automata/dfa.cr`, `src/regex/automata/hir_compiler.cr`, `src/regex/automata/nfa.cr`
  - Progress: forward `Input` span context now follows the vendor `dfa/search.rs` boundary behavior for ranged searches; reverse wrapper and iterator parity still need direct ports
  - Done when: the wrapper stops relying on a custom simplified searcher, richer look-around behavior matches Rust, and the covered rows are `ported`

- [ ] Dense DFA — determinize, minimize, and wire format
  - Upstream scope: `src/dfa/determinize.rs`, `src/dfa/minimize.rs`, `src/dfa/remapper.rs`, serialization hooks in `src/dfa/dense.rs`
  - Inventory ids: `src/dfa/determinize.rs::*`, `src/dfa/minimize.rs::*`, `src/dfa/remapper.rs::*`, serialization-related rows under `src/dfa/dense.rs::*`
  - Red: port determinization/minimization/serialization specs
  - Green: `src/regex/automata/dfa.cr`, `src/regex/automata/dfa_util.cr`, `src/regex/automata/transition_table.cr`, `src/regex/automata/wire.cr`
  - Done when: dense DFA transformation and wire-format parity specs are green

- [ ] Sparse DFA
  - Upstream scope: `src/dfa/sparse.rs`
  - Inventory ids: `src/dfa/sparse.rs::*`
  - Red: port sparse DFA API and serialization specs
  - Green: new sparse DFA implementation files under `src/regex/automata/`
  - Done when: sparse DFA build, query, and serialization parity is demonstrated

- [ ] One-pass DFA
  - Upstream scope: `src/dfa/onepass.rs`
  - Inventory ids: `src/dfa/onepass.rs::*`
  - Red: port one-pass DFA specs
  - Green: new one-pass DFA implementation files under `src/regex/automata/`
  - Done when: one-pass DFA build, search, and serialization parity is demonstrated

- [ ] Thompson NFA — compiler and representation
  - Upstream scope: `src/nfa/thompson/compiler.rs`, `src/nfa/thompson/nfa.rs`, `src/nfa/thompson/builder.rs`, `src/nfa/thompson/literal_trie.rs`, `src/nfa/thompson/range_trie.rs`, `src/nfa/thompson/map.rs`
  - Inventory ids: `src/nfa/thompson/compiler.rs::*`, `src/nfa/thompson/nfa.rs::*`, `src/nfa/thompson/builder.rs::*`, `src/nfa/thompson/literal_trie.rs::*`, `src/nfa/thompson/range_trie.rs::*`, `src/nfa/thompson/map.rs::*`
  - Red: port compiler/builder parity specs
  - Green: `src/regex/automata/nfa.cr`, `src/regex/automata/hir_compiler.cr`
  - Done when: compiler, builder, and representation rows for this slice are `ported`

- [ ] PikeVM search engine
  - Upstream scope: `src/nfa/thompson/pikevm.rs`
  - Inventory ids: `src/nfa/thompson/pikevm.rs::*`
  - Red: port PikeVM search and capture specs
  - Green: new PikeVM implementation files under `src/regex/automata/`
  - Done when: PikeVM search, cache, and capture parity specs are green

- [ ] Backtracking search engine
  - Upstream scope: `src/nfa/thompson/backtrack.rs`
  - Inventory ids: `src/nfa/thompson/backtrack.rs::*`
  - Red: port backtracking search and capture specs
  - Green: new backtracking implementation files under `src/regex/automata/`
  - Done when: backtracking search and heuristic parity is demonstrated

- [ ] Lazy (Hybrid) DFA
  - Upstream scope: `src/hybrid/dfa.rs`, `src/hybrid/search.rs`, `src/hybrid/regex.rs`, `src/hybrid/id.rs`, `src/hybrid/error.rs`
  - Inventory ids: `src/hybrid/*::*`
  - Red: port hybrid DFA build/search/cache specs
  - Green: `src/regex/automata/hybrid.cr`
  - Done when: lazy DFA parity specs are green

- [ ] Meta regex engine
  - Upstream scope: `src/meta/regex.rs`, `src/meta/strategy.rs`, `src/meta/wrappers.rs`, `src/meta/reverse_inner.rs`, `src/meta/stopat.rs`, `src/meta/limited.rs`, `src/meta/literal.rs`
  - Inventory ids: `src/meta/*::*`
  - Red: port meta engine specs
  - Green: new meta engine implementation files under `src/regex/automata/`
  - Done when: meta engine build/search/strategy parity is demonstrated

- [ ] Utilities — Search result primitives
  - Upstream scope: `src/util/search.rs::struct::Span`, `src/util/search.rs::struct::Match`, `src/util/search.rs::struct::HalfMatch`, `src/util/search.rs::enum::Anchored`, `src/util/search.rs::enum::MatchKind`
  - Inventory ids: `src/util/search.rs::struct::Span`, `src/util/search.rs::struct::Match`, `src/util/search.rs::struct::HalfMatch`, `src/util/search.rs::enum::Anchored`, `src/util/search.rs::enum::MatchKind`, `src/util/search.rs::func::must`, `src/util/search.rs::func::offset`, `src/util/search.rs::func::pattern`, `src/util/search.rs::func::len`, `src/util/search.rs::func::is_empty`, `src/util/search.rs::method::Anchored.is_anchored`, `src/util/search.rs::method::Span.range`
  - Red: port primitive-value semantics specs
  - Green: `src/regex/automata/search.cr`
  - Done when: the result primitive API is fully ported and inventory-backed

- [ ] Utilities — Search iteration helpers
  - Upstream scope: `src/util/iter.rs`
  - Inventory ids: `src/util/iter.rs::*`
  - Red: port `Searcher` ownership, half-match advancement, and infallible iterator-constructor specs before broadening into captures iteration
  - Green: `src/regex/automata/search.cr`, `spec/searcher_spec.cr`
  - Progress: `Searcher` now clones `Input` on construction and exposes the half/match iterator wrappers; captures-oriented iterator parity is still missing
  - Done when: `Searcher`, `TryHalfMatchesIter`, `TryMatchesIter`, `HalfMatchesIter`, `MatchesIter`, and captures iteration behavior all match upstream

- [ ] Utilities — Captures and slot management
  - Upstream scope: `src/util/captures.rs`
  - Inventory ids: `src/util/captures.rs::*`
  - Red: port captures specs
  - Green: new captures implementation files under `src/regex/automata/`
  - Done when: capture extraction and slot management parity is demonstrated

- [ ] Utilities — Look-around assertions
  - Upstream scope: `src/util/look.rs`
  - Inventory ids: `src/util/look.rs::*`
  - Red: port look-around specs
  - Green: `src/regex/automata/look.cr`
  - Done when: look-around construction and UTF-8 boundary logic parity is demonstrated

- [ ] Utilities — Byte classes and UTF-8 automata
  - Upstream scope: `src/util/alphabet.rs`, `src/util/utf8.rs`
  - Inventory ids: `src/util/alphabet.rs::*`, `src/util/utf8.rs::*`
  - Red: port byte-class and UTF-8 specs
  - Green: `src/regex/automata/byte_classes.cr`, `src/regex/automata/byte_set.cr`, `src/regex/automata/utf8_sequences.cr`
  - Done when: byte-class partitioning and UTF-8 automaton parity is demonstrated

- [ ] Utilities — Prefilters
  - Upstream scope: `src/util/prefilter/*`
  - Inventory ids: `src/util/prefilter/*::*`
  - Red: port prefilter selection and matching specs
  - Green: new prefilter implementation files under `src/regex/automata/`
  - Done when: literal-acceleration parity is demonstrated

- [ ] Utilities — Serialization and escaping
  - Upstream scope: `src/util/wire.rs`, `src/util/escape.rs`
  - Inventory ids: `src/util/wire.rs::*`, `src/util/escape.rs::*`
  - Red: port wire-format and escaping specs
  - Green: `src/regex/automata/wire.cr`
  - Done when: serialization/deserialization parity is demonstrated

- [ ] Utilities — PatternSet
  - Upstream scope: `src/util/search.rs::struct::PatternSet`, `src/util/search.rs::struct::PatternSetInsertError`, `src/util/search.rs::struct::PatternSetIter`
  - Inventory ids: `src/util/search.rs::struct::PatternSet`, `src/util/search.rs::struct::PatternSetInsertError`, `src/util/search.rs::struct::PatternSetIter`, `src/util/search.rs::func::capacity`, `src/util/search.rs::func::clear`, `src/util/search.rs::func::contains`, `src/util/search.rs::func::insert`, `src/util/search.rs::func::iter`, `src/util/search.rs::func::is_empty`, `src/util/search.rs::func::is_full`, `src/util/search.rs::func::len`, `src/util/search.rs::func::remove`, `src/util/search.rs::func::try_insert`, `src/util/search.rs::method::PatternSet.new`
  - Red: port PatternSet specs
  - Green: `src/regex/automata/search.cr` or a focused support file
  - Done when: PatternSet API parity is demonstrated

- [ ] Utilities — Shared infrastructure helpers
  - Upstream scope: `src/util/pool.rs`, `src/util/lazy.rs`, `src/util/iter.rs`, `src/util/primitives.rs`, `src/util/sparse_set.rs`, `src/util/start.rs`, `src/util/syntax.rs`, `src/util/interpolate.rs`, `src/util/int.rs`, `src/util/empty.rs`, `src/util/memchr.rs`
  - Inventory ids: `src/util/pool.rs::*`, `src/util/lazy.rs::*`, `src/util/iter.rs::*`, `src/util/primitives.rs::*`, `src/util/sparse_set.rs::*`, `src/util/start.rs::*`, `src/util/syntax.rs::*`, `src/util/interpolate.rs::*`, `src/util/int.rs::*`, `src/util/empty.rs::*`, `src/util/memchr.rs::*`
  - Red: port helper specs module by module, not as one lump
  - Green: supporting files under `src/regex/automata/`
  - Done when: each helper family has its own proven parity slice in the ledger

## Completed

- [x] Utilities — Input configuration API
  - Inventory ids: `src/util/search.rs::struct::Input`, `src/util/search.rs::func::new`, `src/util/search.rs::func::span`, `src/util/search.rs::func::range`, `src/util/search.rs::func::anchored`, `src/util/search.rs::func::earliest`, `src/util/search.rs::func::set_range`, `src/util/search.rs::func::set_start`, `src/util/search.rs::func::set_end`, `src/util/search.rs::func::set_anchored`, `src/util/search.rs::func::set_earliest`, `src/util/search.rs::func::haystack`, `src/util/search.rs::func::start`, `src/util/search.rs::func::end`, `src/util/search.rs::func::get_span`, `src/util/search.rs::func::get_range`, `src/util/search.rs::func::get_anchored`, `src/util/search.rs::func::get_earliest`, `src/util/search.rs::func::is_done`, `src/util/search.rs::func::is_char_boundary`, `src/util/search.rs::struct::Span`, `src/util/search.rs::method::Span.range`
  - Specs: `spec/search_input_spec.cr`
  - Crystal: `src/regex/automata/search.cr`

- [x] DFA API — quit bytes, unicode word boundaries, universal start
  - Inventory ids: `tests/dfa/api.rs::test::quit_fwd`, `tests/dfa/api.rs::test::quit_panics`, `tests/dfa/api.rs::test::quit_rev`, `tests/dfa/api.rs::test::unicode_word_implicitly_works`, `tests/dfa/api.rs::test::universal_start_search`
  - Specs: `spec/dfa_api_spec.cr`

- [x] Search errors and start/build errors
  - Inventory ids: `src/util/search.rs::struct::MatchError`, `src/util/search.rs::enum::MatchErrorKind`, `src/dfa/automaton.rs::enum::StartError`, `src/dfa/dense.rs::struct::BuildError`
  - Crystal: `src/regex/automata/errors.cr`, `src/regex/automata/automaton.cr`
