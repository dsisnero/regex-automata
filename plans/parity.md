# Parity Plan

## Baseline and inventory rules

- Rust source and Rust tests in `vendor/regex/regex-automata/` are the behavioral source of truth. The pinned vendor is `72d650cb0a880a01ab6dc2137c0888e8f89740f7` (`regex-automata` 0.4.18, `regex-syntax` 0.8.11). `git fetch origin master` on 2026-10-05 confirmed that this is also `origin/master`; no submodule pointer update is pending.
- The previous plan's completed checkboxes were not a valid whole-repository signoff: its curated ledger used older, regex-derived identifiers and its generated source manifest did not cover the current Rust tree-sitter identifiers. Treat prior port claims as evidence to verify, not completion evidence.
- The binding source inventory is `plans/inventory/rust_source_parity.tsv`: 1,936 Rust source API items discovered from `src/` with tree-sitter. The binding test inventory is `plans/inventory/rust_test_parity.tsv`: 220 Rust unit, integration, regression, fuzz, generated, and suite entries discovered from `src/` and `tests/` with the regex fallback. The fallback is intentional: the current tree-sitter test classifier recognizes only four constants and misses `#[test]` attributes.
- The strict source check was re-verified on 2026-10-09 with a workspace-local `temp/tools/chiasmus-discover` compatibility copy linked against Homebrew tree-sitter 0.27 and the bundled Rust grammar: `PORT_SCOPE_INCLUDE=src PORT_PARSER=tree-sitter` passed with 1,936 tracked items. The distributed discovery binary is linked against tree-sitter 0.26, so the compatibility copy is intentionally ephemeral under `temp/`; repeatable clean-room discovery still needs a compatible bundled binary or a project-owned rebuild step before final signoff.
- `plans/inventory/rust_port_inventory.tsv` is stale against the current source identifiers. It must be reconciled before any feature can be closed: every generated source/test row needs a `ported`, `partial`, `skipped`, or `intentional_divergence` disposition, with Crystal references and an explanation for every non-port.
- “Done” means behavior and public API are proven by a Crystal spec derived from the nearest Rust test. Rust ownership, trait-object, auto-trait, `Debug`, memory-layout, cache-line, and unsafe implementation details may be skipped only when the ledger records why they have no Crystal-observable equivalent.

## Execution policy

1. Work feature by feature in the order below. Read the Rust source and its nearest Rust tests before changing Crystal.
2. Port the next missing behavior as a failing Crystal spec, implement the smallest faithful change, and repeat until that feature's source and test rows are reconciled.
3. Run focused specs during the loop. Before checking a feature, run its relevant vendor tests where feasible, `make format`, `make lint`, `make test`, the three parity checks, and `git diff --check`.
4. Commit each completed feature separately with its Crystal code, specs, curated-ledger changes, generated manifest refresh when needed, and this plan update.
5. Do not mark a box complete merely because a Crystal file has a similarly named API. Delegation to an existing engine is only valid after identical range, anchoring, captures, errors, iteration, and serialization behavior are demonstrated.

## Current focus

- [ ] Reconcile the parity ledger and test harness
  - Scope: every row in `plans/inventory/rust_source_parity.tsv` and `plans/inventory/rust_test_parity.tsv`; existing `plans/inventory/rust_port_inventory.tsv`; all Rust test harness modules in `tests/`.
  - Work: replace stale identifier rows with current tree-sitter IDs, preserve verified mappings only after checking them, and add source/test notes for Crystal-native divergences. Create a repeatable way to run or transcribe the Rust suite matrices instead of relying on handwritten spot checks.
  - Done when: all generated rows are present in the curated ledger, source/test/port inventory checks pass under their recorded parser modes, and no unverified `ported` status remains.

- [x] Public facade, shared types, and crate configuration
  - Scope: `src/lib.rs`, `src/macros.rs`, `src/dfa/mod.rs`, `src/hybrid/mod.rs`, `src/meta/mod.rs`, `src/nfa/mod.rs`, `src/nfa/thompson/mod.rs`, `src/util/mod.rs`, and every public type/re-export/error surfaced through them.
  - Done: the Crystal entry point loads the primary engine namespaces and shared search/type surface. Rust Cargo feature gates and macro expansion are build-system mechanisms with no Crystal runtime counterpart; the only generated source row in this module layer, the private DFA `DEAD` sentinel, maps to `DFA::DEAD_STATE_ID` and is proven to remain `StateID::ZERO`.

- [x] Search result primitives
  - Scope: `src/util/search.rs::{Span,HalfMatch,Match}`.
  - Done: `Span`, `HalfMatch`, and `Match` expose the Rust result API, including `Match#span` versus `Match#range`, `len`, `is_empty`, and the upstream inclusive-end `Span#contains` behavior. Crystal-friendly aliases remain additive.

- [x] Input configuration and anchoring
  - Scope: `src/util/search.rs::{Input,Anchored}`.
  - Done: ranges, done sentinel, UTF-8 boundaries, anchor mode, earliest mode, String/Bytes construction, and clone behavior are covered. Crystal represents Rust's `Anchored::Pattern(PatternID)` as `Anchored::Pattern` plus `Input#pattern`; this intentional language-level divergence is documented in the ledger and tested through clone.

- [x] Match errors
  - Scope: `src/util/search.rs::{MatchError,MatchErrorKind}`.
  - Done: every structured kind, constructor, payload, equality, and unsupported-anchor context is covered. Rust Debug formatting remains a documented Crystal-native divergence.

- [x] Pattern sets and generic search iteration
  - Scope: `src/util/search.rs::{PatternSet,PatternSetIter}` and `src/util/iter.rs`.
  - Done: capacity/error limits, ordering, forward/reverse exhaustion, empty-match handling, fallible/infallible conversion, capture snapshots, error propagation, and retained input are covered. Rust Debug and size-hint protocols are documented Crystal-native divergences.

- [x] Capture slots and interpolation
  - Scope: `src/util/captures.rs` and `src/util/interpolate.rs`.
  - Done: group metadata, named/numeric lookup, slot ordering, all capture iterator variants, malformed metadata, byte/string interpolation (including append destinations), and snapshot ownership are covered. Rust Debug/iterator-hint APIs and exact memory-layout accounting are documented Crystal-native divergences; extraction uses a runtime group count in place of Rust's const-generic array length.

- [x] Start configuration and start-byte map
  - Scope: `src/util/start.rs`.
  - Done: forward/reverse `Input` configuration, look-behind selection, anchor builders, every start classification, custom line terminators, and exact 256-byte wire read/write error behavior are covered. Rust Debug formatting is a documented Crystal-native divergence.

- [x] Look-around assertions
  - Scope: `src/util/look.rs`.
  - Done: line/CRLF anchors, ASCII and Unicode word/half-boundary behavior, assertion-set algebra and representation, Unicode availability, and assertion-sensitive byte classes are covered. Crystal has one optimized dispatch path in place of Rust's inline duplicates; debug formatting differs only in its wrapper syntax.

- [ ] Utility data structures, syntax, Unicode, and wire helpers
  - Scope: `src/util/{alphabet,determinize,escape,int,interpolate,lazy,memchr,pool,primitives,sparse_set,syntax,utf8,wire}.rs` and `src/util/unicode_data/**`.
  - Work: reconcile byte classes, determinization state encoding, integer/range boundaries, escaping, interpolation, lazy/pool semantics, sparse-set behavior, syntax configuration, Unicode word data, endianness, alignment, labels, and serialization errors. Small-index primitive wire conversion, typed decode errors, UTF-8 helper behavior, syntax multi-pattern parsing, and contextual serialization errors are now covered; Crystal constructor/trait/indexing differences, Rust-private numeric-cast traits, split AST/HIR parser hooks, and endian-trait implementation details are explicitly recorded in the ledger. Explicitly separate semantic behavior from Rust-only ownership/thread/layout optimizations.

- [ ] Prefilter algorithms and search contracts
  - Scope: `src/util/prefilter/{mod,aho_corasick,byteset,memchr,memmem,teddy}.rs`.
  - Work: generic `find`/prefix construction plus dense-DFA and hybrid forward/overlapping integration now preserve bounded candidates, pending leftmost matches, and context-sensitive start-state restarts. PikeVM already applies candidates in regular and overlapping NFA loops; the bounded backtracker delegates that behavior only after its capacity guard, with both paths covered. Meta routes core candidates through PikeVM and covers automatic/explicit/literal/reverse strategy admission. Still port or explicitly classify actual strategy selection (`aho_corasick`, byteset, memchr, memmem, teddy) and false-positive, diagnostic, and memory contracts before closing this feature.

- [ ] Thompson NFA construction, representation, and compiler
  - Scope: `src/nfa/thompson/{nfa,builder,compiler,literal_trie,range_trie,map,error}.rs`.
  - Work: prove public constructors/configuration, captures policy, all state variants and transitions, byte-class analysis, look sets, literal/range trie compilation, reverse construction, limits, errors, and memory/query APIs. `HirCompilerConfig` tracks explicit overrides and merges them as Rust's sparse configuration overlay, including explicit default values. Builder limits are enforced as states are added and when unions grow during patching; the estimate retains Rust's 32-byte intermediate-state baseline plus transition storage, with Crystal allocation-layout differences classified. The hand-builder now has Rust's pattern lifecycle, state constructors, patching, clear/configuration, and final start/capture assembly; reverse union IDs are tracked only during construction because Crystal reuses the final union state type. Its malformed-graph and capture error cases still need exhaustive validation. The HIR compiler follows Rust's four repetition construction paths, including shared exits for bounded repetition; it now compiles capture starts before their children and concatenations incrementally in search order rather than precompiling an array of children. Pinned state-graph assertions cover repetition and all three capture policies. Parsed `a|b` still has a different state graph because the installed Crystal regex-syntax parser emits literal alternation where Rust regex-syntax emits a byte class; reconcile that dependency normalization without changing hand-built HIR semantics. The three Rust builder doctests and its local unit test passed against the pinned vendor. Reconcile private graph-layout helpers individually rather than claiming a final NFA is enough.

- [ ] PikeVM and bounded backtracker engines
  - Scope: `src/nfa/thompson/{pikevm,backtrack}.rs` and `tests/nfa/thompson/{pikevm,backtrack}/**`.
  - Work: PikeVM uses cache-owned contiguous per-state slot storage plus a scratch row, exposed through bounded Crystal `Slice` views; this preserves Rust's reuse and avoids per-thread capture-slot allocation/copying in the search hot path. The bounded backtracker now implements Rust's explicit DFS stack, scoped capture restoration, and reusable `(state, relative-offset)` visited bitset rather than delegating to PikeVM. Remaining validation is the complete vendored fixture harness, including quit errors and adversarial cache/limit configurations.

- [ ] Dense DFA runtime and automaton interface
  - Scope: `src/dfa/{automaton,accel,dense,search,special,start}.rs`.
  - Work: reconcile the full `Automaton` contract, state classification, start-state selection, EOI transitions, accelerator APIs, leftmost and overlapping forward/reverse search, match-kind behavior, quit handling, Unicode boundary heuristics, byte classes, and all public metadata/query methods.
  - Tests: `tests/dfa/{api,regression,suite}.rs`, including pending-prefilter, universal start, per-pattern starts, and serialized start-state rejection regressions.

- [ ] Dense DFA compilation, transformations, and serialization
  - Scope: `src/dfa/{determinize,minimize,remapper}.rs` plus mutation/serialization portions of `src/dfa/dense.rs`.
  - Work: prove limits and failure precedence; remap/minimize/truncate/swap/shuffle state-ID invariants; transition, EOI, start-table, special-state, match-map, accelerator, and pattern-map coherence; all native/little/big-endian read/write paths; and malformed-wire rejection. Dense construction now applies a compact final-order permutation while rebuilding transition and start tables, rather than Rust's temporary swap-and-repair cycle; it preserves the premultiplied-ID invariant and avoids hash lookups in the remap pass. Rust's determinizer runner is folded into Crystal's dense Builder and preserves its start grouping, cached subset construction, quit overrides, and public size-limit behavior. Its private scratch-StateBuilder reuse and exact allocator accounting are not yet mirrored; measure allocations before adding a Crystal pool or changing the current deterministic estimate. The minimizer now uses a reverse byte-class/EOI transition index and Hopcroft waiting partitions; Crystal uses arrays and Boolean source marks in place of Rust's reference-counted ordered StateSet. One-pass still needs its real compiled-table implementation before the remapper family can close.

- [ ] Dense and sparse regex wrappers
  - Scope: `src/dfa/{regex,sparse}.rs` and all dense/sparse integration, fuzz, generated, and suite tests under `tests/dfa/**`, `tests/fuzz/**`, and `tests/gen/**`.
  - Work: complete wrapper constructors/builders, iterators, captures, reverse and always-anchored behavior, sparse representation/query/serialization, and dense-to-sparse conversion. A dense-backed sparse wrapper is an intentional divergence until its public API and wire behavior are either made equivalent or all differing Rust rows are documented as such.

- [ ] One-pass DFA engine
  - Scope: `src/dfa/onepass.rs` and `tests/dfa/onepass/**`.
  - Work: replace or fully justify PikeVM delegation; prove one-pass admission, transition/state tables, epsilon/look handling, capture slots, cache behavior, limits, all builder/config APIs, and search error semantics. Admission now traverses the Thompson NFA and rejects duplicate epsilon paths, conflicting byte-class transitions, and look kinds outside Rust's packed transition representation instead of relying on a list of pattern-string exceptions. The compiled table executes anchored searches with explicit capture slots, supported look assertions, and UTF-8 empty-match filtering through a reusable cache, sizing scratch slots to each caller buffer; match states are shuffled into a tail so the search loop uses the same cheap state-ID comparison as Rust. The obsolete PikeVM fallback allocation is removed. The source-level acceptance/rejection matrix is now ported, and a fixture-driven runner covers the vendored anchored corpus for every admitted one-pass pattern. The remaining work is the general upstream TOML harness and cross-engine adversarial coverage.

- [x] Lazy (hybrid) DFA engine
  - Scope: `src/hybrid/{dfa,error,id,regex,search}.rs` and `tests/hybrid/**`.
  - Complete: lazy determinization/cache capacity and clearing, state-ID/error encoding, dense/hybrid regex wrappers, forward/reverse/overlap search, prefilter safety, quit behavior, Unicode, specialized starts, NFA shrink, and builder/config/cache query APIs are mapped to `hybrid.cr` and covered by the hybrid parity specs. The wrapper cache now reports the same aggregate cache memory accounting as its component caches. The implementation remains genuinely lazy rather than a dense fallback, including cache-limit and lazy-state failure behavior.

- [ ] Meta regex engine, strategy selection, and guards
  - Scope: `src/meta/{error,limited,literal,prefix,regex,reverse_inner,reverse_suffix,stopat,strategy,wrappers}.rs` and `tests/meta/**`.
  - Work: prove engine selection/fallback, literal and prefix acceleration, reverse DFA/suffix/inner safety proofs, limited/stop-at guards, captures and multi-pattern behavior, configured engine restrictions, cache/pool behavior, and error propagation. Meta NFA size failures now retain their configured limit and remain distinct from syntax failures; reverse limited searches cover both minimum-start and quit-offset guards. Reverse-anchored selection now tries dense first, then retains a resettable hybrid cache fallback when dense construction is unavailable, covering the upstream `\\w+Holmes$` matrix. Reverse-inner now builds a dense reverse/forward pair when possible and falls back to resettable lazy reverse/forward DFAs, with bounded reverse and stop-at forward guards mirroring Rust's anti-quadratic fallback. Retain the recently added reverse safety tests, but revalidate every helper and private admission condition against Rust before treating the strategy family as complete.

- [ ] Cross-engine conformance and adversarial regression suite
  - Scope: all engine-facing tests in `tests/dfa/**`, `tests/hybrid/**`, `tests/meta/**`, `tests/nfa/**`, plus fuzz/generated fixtures and Rust unit tests under `src/**`.
  - Work: build shared fixture-driven Crystal specs that run the same pattern/input/configuration matrices through dense, sparse, one-pass, hybrid, PikeVM, backtracker, and Meta where Rust supports them. Include malformed serialization and transformed-DFA adversarial cases.
  - Done when: each test-manifest row is mapped to a Crystal test or an explicit non-port rationale, with no unexplained test-family omission.

- [ ] Final vendor signoff
  - Scope: the entire `vendor/regex/regex-automata` tree, all inventories, and all Crystal source/spec files.
  - Work: run `make install`, `make format`, `make lint`, `make test`, the source/test/port inventory checks, and an adversarial Rust-vs-Crystal pass. Re-fetch vendor before signing off and repeat the audit if its revision changes.
  - Done when: every generated row has a reviewed curated status; all non-portable Rust internals are explicitly classified; all quality gates are green; and this plan contains no unchecked feature.

## Historical evidence (not signoff)

The previous implementation work added useful focused coverage for dense start-state validation, pending-prefilter behavior, reverse Meta strategy safety, pool capacity, and DFA transformation ID-space handling. Those changes remain candidates for ledger mappings, but they are deliberately not represented as completed repository-wide parity until the current manifests and upstream tests verify them.
