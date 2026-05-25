# Parity Plan

## Execution Policy

- Each top-level checkbox is a commit-sized git feature, not a convenient small method patch.
- Work should continue until the active top-level feature has its intended red-to-green spec set, the corresponding inventory rows are updated, quality gates pass, and the branch is ready for a commit.
- Avoid stopping after isolated accessors, aliases, or bookkeeping changes when they are only one fragment of a larger feature workflow already in flight.
- After a top-level feature reaches parity for its declared scope, commit immediately before moving to the next feature.
- Use inventory rows to track completeness inside a feature, but use this plan to decide when a branch-sized unit is actually done.

## Current Focus

- [x] Dense DFA core engine parity
  - Upstream scope: `src/dfa/dense.rs`, `src/dfa/automaton.rs`, `src/dfa/accel.rs`, `src/dfa/start.rs`, `src/dfa/special.rs`
  - Inventory ids: `src/dfa/dense.rs::*`, `src/dfa/automaton.rs::*`, `src/dfa/accel.rs::*`, `src/dfa/start.rs::*`, `src/dfa/special.rs::*`
  - Workflow: finish builder/config/start-state/search behavior as one coherent engine feature instead of landing isolated helpers
  - Red: port the remaining builder, anchored/unanchored start-state, reverse-search, overlapping-search, and `MatchKind::All` parity specs needed to prove the engine surface
  - Green: `src/regex/automata/dfa.cr`, `src/regex/automata/automaton.cr`, `src/regex/automata/accel.cr`, `src/regex/automata/special.cr`, `src/regex/automata/start_config.cr`, `src/regex/automata/start_table.cr`
  - Progress: config aliases, Unicode boundary handling, metadata accessors, dense roundtrip helpers, reverse overlap, vendor-style `MatchKind::All` aggregation, accelerator APIs, syntax configuration, prefilter attachment, and size-limit signaling are now ported and covered
  - Done when: dense DFA engine semantics match upstream on the intended builder/search/start-state parity suite and the covered rows are ready for one commit-sized checkpoint

- [x] Dense DFA regex wrapper parity
  - Upstream scope: `src/dfa/regex.rs`, plus iterator behavior from `src/util/iter.rs`
  - Inventory ids: `src/dfa/regex.rs::*`
  - Workflow: close the wrapper as a user-facing feature, including the iterator/search contracts it exposes, before moving on
  - Red: port empty-match iteration, UTF-8 iteration, always-anchored, reverse-wrapper, and builder-validation parity specs before adding more surface area
  - Green: `src/regex/automata/dfa_regex.cr`, `src/regex/automata/dfa.cr`, `src/regex/automata/hir_compiler.cr`, `src/regex/automata/nfa.cr`
  - Progress: ranged `try_search`, reverse-start recovery, empty-match iteration, UTF-8-safe iterator behavior, dense/syntax builder aliases, and sparse wrapper constructors are now covered
  - Done when: the wrapper stops relying on a custom simplified searcher, richer look-around behavior matches Rust, and the covered rows are strong enough for a dedicated commit

- [x] Dense DFA compile pipeline and wire format parity
  - Upstream scope: `src/dfa/determinize.rs`, `src/dfa/minimize.rs`, `src/dfa/remapper.rs`, serialization hooks in `src/dfa/dense.rs`
  - Inventory ids: `src/dfa/determinize.rs::*`, `src/dfa/minimize.rs::*`, `src/dfa/remapper.rs::*`, serialization-related rows under `src/dfa/dense.rs::*`
  - Workflow: treat determinization, minimization, remapping, and validation-order behavior as one compiler/wire-format feature instead of dripping out serializer nits
  - Red: port determinization/minimization/serialization specs, including validation-order and size-limit behavior, before calling this feature done
  - Green: `src/regex/automata/dfa.cr`, `src/regex/automata/dfa_util.cr`, `src/regex/automata/transition_table.cr`, `src/regex/automata/wire.cr`
  - Progress: constructor aliases, always/never round trips, endianness-aware round trips, buffer-write helpers, determinization scratch-limit failures, dense minimization, and deserialize validation-order hardening are now covered; `to_sparse` is deferred to the Sparse DFA feature because there is still no sparse engine implementation
  - Done when: dense DFA transformation and wire-format parity specs are green and the remaining compiler/validation rows can be committed as one feature

- [x] Sparse DFA
  - Upstream scope: `src/dfa/sparse.rs`
  - Inventory ids: `src/dfa/sparse.rs::*`
  - Workflow: deliver sparse build/search/serialization as a complete engine feature, not as piecemeal type stubs
  - Red: port sparse DFA API and serialization specs
  - Green: new sparse DFA implementation files under `src/regex/automata/`
  - Progress: sparse constructors, dense-to-sparse conversion, metadata accessors, prefilter attachment, wrapper serialization helpers, heuristic Unicode quit behavior, and sparse regex convenience builders are now covered
  - Done when: sparse DFA build, query, and serialization parity is demonstrated

- [ ] One-pass DFA
  - Upstream scope: `src/dfa/onepass.rs`
  - Inventory ids: `src/dfa/onepass.rs::*`
  - Workflow: land one-pass build/search/serialization as one branch-sized feature
  - Red: port one-pass DFA specs
  - Green: new one-pass DFA implementation files under `src/regex/automata/`
  - Done when: one-pass DFA build, search, and serialization parity is demonstrated

- [ ] Thompson NFA — compiler and representation
  - Upstream scope: `src/nfa/thompson/compiler.rs`, `src/nfa/thompson/nfa.rs`, `src/nfa/thompson/builder.rs`, `src/nfa/thompson/literal_trie.rs`, `src/nfa/thompson/range_trie.rs`, `src/nfa/thompson/map.rs`
  - Inventory ids: `src/nfa/thompson/compiler.rs::*`, `src/nfa/thompson/nfa.rs::*`, `src/nfa/thompson/builder.rs::*`, `src/nfa/thompson/literal_trie.rs::*`, `src/nfa/thompson/range_trie.rs::*`, `src/nfa/thompson/map.rs::*`
  - Workflow: finish one compiler/representation checkpoint that includes builder behavior and core graph representation together
  - Red: port compiler/builder parity specs
  - Green: `src/regex/automata/nfa.cr`, `src/regex/automata/hir_compiler.cr`
  - Done when: compiler, builder, and representation rows for this slice are `ported`

- [ ] PikeVM search engine
  - Upstream scope: `src/nfa/thompson/pikevm.rs`
  - Inventory ids: `src/nfa/thompson/pikevm.rs::*`
  - Workflow: land PikeVM search and capture behavior as one runnable engine milestone
  - Red: port PikeVM search and capture specs
  - Green: new PikeVM implementation files under `src/regex/automata/`
  - Done when: PikeVM search, cache, and capture parity specs are green

- [ ] Backtracking search engine
  - Upstream scope: `src/nfa/thompson/backtrack.rs`
  - Inventory ids: `src/nfa/thompson/backtrack.rs::*`
  - Workflow: land backtracking search and heuristic behavior as one engine feature
  - Red: port backtracking search and capture specs
  - Green: new backtracking implementation files under `src/regex/automata/`
  - Done when: backtracking search and heuristic parity is demonstrated

- [ ] Lazy (Hybrid) DFA
  - Upstream scope: `src/hybrid/dfa.rs`, `src/hybrid/search.rs`, `src/hybrid/regex.rs`, `src/hybrid/id.rs`, `src/hybrid/error.rs`
  - Inventory ids: `src/hybrid/*::*`
  - Workflow: close one coherent lazy-DFA feature including build/search/cache, not isolated helper deltas
  - Red: port hybrid DFA build/search/cache specs
  - Green: `src/regex/automata/hybrid.cr`
  - Done when: lazy DFA parity specs are green

- [ ] Meta regex engine
  - Upstream scope: `src/meta/regex.rs`, `src/meta/strategy.rs`, `src/meta/wrappers.rs`, `src/meta/reverse_inner.rs`, `src/meta/stopat.rs`, `src/meta/limited.rs`, `src/meta/literal.rs`
  - Inventory ids: `src/meta/*::*`
  - Workflow: land meta-engine construction, strategy selection, and wrapper behavior as a complete feature family
  - Red: port meta engine specs
  - Green: new meta engine implementation files under `src/regex/automata/`
  - Done when: meta engine build/search/strategy parity is demonstrated

- [x] Utilities — Search result primitives
  - Upstream scope: `src/util/search.rs::struct::Span`, `src/util/search.rs::struct::Match`, `src/util/search.rs::struct::HalfMatch`, `src/util/search.rs::enum::Anchored`, `src/util/search.rs::enum::MatchKind`
  - Inventory ids: `src/util/search.rs::struct::Span`, `src/util/search.rs::struct::Match`, `src/util/search.rs::struct::HalfMatch`, `src/util/search.rs::enum::Anchored`, `src/util/search.rs::enum::MatchKind`, `src/util/search.rs::func::must`, `src/util/search.rs::func::offset`, `src/util/search.rs::func::pattern`, `src/util/search.rs::func::len`, `src/util/search.rs::func::is_empty`, `src/util/search.rs::method::Anchored.is_anchored`, `src/util/search.rs::method::Span.range`
  - Red: port primitive-value semantics specs
  - Green: `src/regex/automata/search.cr`
  - Done when: the result primitive API is fully ported and inventory-backed

- [x] Utilities — Search iteration helpers
  - Upstream scope: `src/util/iter.rs`
  - Inventory ids: `src/util/iter.rs::*`
  - Workflow: finish the full iterator workflow, including captures-related advancement rules, before treating this as done
  - Red: port `Searcher` ownership, half-match advancement, and infallible iterator-constructor specs before broadening into captures iteration
  - Green: `src/regex/automata/search.cr`, `spec/searcher_spec.cr`
  - Progress: `Searcher` now clones `Input` on construction and exposes half, match, and captures iterators, including empty-match advancement and cloned captures snapshots
  - Done when: `Searcher`, `TryHalfMatchesIter`, `TryMatchesIter`, `HalfMatchesIter`, `MatchesIter`, and captures iteration behavior all match upstream

- [x] Utilities — Captures and slot management
  - Upstream scope: `src/util/captures.rs`
  - Inventory ids: `src/util/captures.rs::*`
  - Red: port captures specs
  - Green: new captures implementation files under `src/regex/automata/`
  - Done when: capture extraction and slot management parity is demonstrated

- [x] Utilities — Look-around assertions
  - Upstream scope: `src/util/look.rs`
  - Inventory ids: `src/util/look.rs::*`
  - Red: port look-around specs
  - Green: `src/regex/automata/look.cr`
  - Progress: look assertion enums, look-set algebra and repr I/O, configurable look matching, UTF-8-aware Unicode word-boundary handling, and the upstream look matcher/set parity specs are now covered
  - Done when: look-around construction and UTF-8 boundary logic parity is demonstrated

- [x] Utilities — Byte classes and UTF-8 automata
  - Upstream scope: `src/util/alphabet.rs`, `src/util/utf8.rs`
  - Inventory ids: `src/util/alphabet.rs::*`, `src/util/utf8.rs::*`
  - Red: port byte-class and UTF-8 specs
  - Green: `src/regex/automata/byte_classes.cr`, `src/regex/automata/byte_set.cr`, `src/regex/automata/utf8_sequences.cr`
  - Progress: ByteClasses and Unit now follow upstream EOI-aware alphabet semantics, byte-class iterators and representative/element traversal are covered, and shared UTF-8 decode/boundary helpers now live in `utf8_sequences.cr` and back the look-around logic
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
  - Workflow: still port helper specs module by module, but each module family should finish at a commit boundary instead of stopping on isolated utility methods
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
