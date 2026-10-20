# Regex-automata parity roadmap

## Contract and evidence

- Source of truth: the checked-in `vendor/regex/regex-automata/` at commit
  `72d650cb0a880a01ab6dc2137c0888e8f89740f7` (regex-automata 0.4.18).
  Do not substitute remembered Rust behavior or a newer upstream revision.
- Working source ledger: [rust_port_inventory.tsv](inventory/rust_port_inventory.tsv)
  (1,936 Rust API items: 1,248 `ported`, 369 `missing`, 126 `partial`, 188
  `intentional_divergence`, 5 `skipped`). Test ledger:
  [rust_test_parity.tsv](inventory/rust_test_parity.tsv) (220 rows: 151
  `ported`, 57 `partial`, 12 `intentional_divergence`). These are **review
  queues**, not a count of absent behaviors or a completion percentage. The
  generated manifests are item inventories, so a file-level pass is also
  required for private algorithms without discovered rows.
- Prior completed work, Rust references, focused test evidence, and the old
  fine-grained checklist are preserved in [parity-history.md](parity-history.md).
  Its unchecked boxes are not additional commit gates. In particular, the
  hybrid eight-mode TOML suite and 180-row source audit are recorded there as
  complete; the old hybrid parent/child checkbox mismatch is historical.
- Existing Crystal specs passing, API names matching, or Crystal-to-Crystal
  serialization round trips do **not** prove Rust parity. A row closes only
  after its named vendor source/test/fixture behavior is checked, with a
  Crystal spec or a precise non-port rationale. Correct stale `ported` and
  divergence claims during the phase that owns them.
- `tests/lib.rs` loads 25 TOML groups containing **1,194** `[[test]]` cases at
  this pin (counted by the new reader and the source delimiters). The old
  history's 1,203 figure was incorrect; suite expansions and engine-specific
  exclusions must be counted separately.
- Ten test rows that had labeled Crystal's dense/sparse wire layout or pooled
  mutex as an `intentional_divergence` are now `partial`. Native vendor wire
  tests and the pool hot-path cost have not been proven unnecessary; phases 2
  and 5 own those decisions.

## Feature-loop rules

Each numbered phase below is **one substantial, coherent feature and one
commit**, not a list of helper-sized stopping points. Complete all of its
source, tests, ledger updates, and documentation before checking its box.
If vendor review reveals a genuinely independent larger feature, add a linked
`plans/feature-<name>.md` plan and a phase here before implementation; do not
hide new work in a catch-all or close a phase with known material gaps.

For each phase: read the cited Rust implementation and nearest Rust tests;
port the failing Crystal tests first; implement through small red-green
cycles; run focused Rust/Crystal checks, then `make install`, `make format`,
`make lint`, `make test`, `make parity`, `git diff --check`,
`crystal tool format --check src spec`, and `crystal build --no-codegen`
before its single `port:` commit. Keep generated temporary files under
`./temp`. Record exact upstream case IDs, supported suite modes, exclusions,
and any untested cases. Do not weaken vendor expectations.

Follow Rust's algorithms and optimization decisions, using Crystal idioms
only where they preserve behavior. For any remaining structural divergence,
document the Rust path, Crystal path, why a direct port is infeasible or
inappropriate, observable equivalence, and hot-path cost. A missing Crystal
standard-library primitive alone does not prove that Teddy or another Rust
optimization is impossible to port. Because this host is heavily loaded,
single-run timing is not performance evidence; defer performance signoff or
use controlled, repeated measurements and retain the previous baseline.

## Active feature phases (complete in order)

Current: **phase 2**. Phase 1 closed with the shared vendor fixture reader
driving the existing hybrid and one-pass anchored runners. Tests went red on
the absent reader and on explicit `false` being replaced by a default; the
green parser preserves byte haystacks, capture spans, bounds, and case IDs.
The eight hybrid modes selected 1,147 or 1,148 cases each and passed 9,178
Crystal examples; the pinned Rust hybrid integration suite passed 8/8 tests.
The full Crystal suite passed 10,296 examples, and `make install`, formatting,
lint, parity, no-codegen build, and whitespace checks passed. The 220-row
test ledger was checked for status, evidence references, and live paths;
ten overclaimed wire/pool divergences were returned to `partial`. The new
file map covers all 72 Rust source files, including 18 without API rows.
README examples were replaced with a compiled current Meta example. The
`shard.yml` `Logos Maintainers` author field still requires maintainer
confirmation; no authorship was inferred or changed.

- [x] **1. Vendor suite harness and trustworthy inventory.** Port the shared
  `tests/lib.rs` input/capture/match-kind contract and the 25 TOML files it
  loads from `vendor/regex/testdata/` into one reusable, byte-preserving
  Crystal fixture runner. Include bounds, anchoring, match kinds, captures,
  expected compilation/search failures, case IDs, and each engine's actual
  Rust skip/blacklist rules; publish per-engine/per-mode counts rather than
  reusing a spot-check suite as full coverage. Reconcile the 220 test rows and
  stale facade/utility source rows against executable specs, and add a
  file-level module map for private Rust algorithms missed by API discovery
  (including `src/util/empty.rs`). Verify README examples and metadata claims;
  flag maintainer-only facts instead of guessing. **Gate:** the runner can
  reproduce vendor selection/results for the already-ported hybrid eight-mode
  suite, inventory checks pass, and no reviewed row is mislabeled `ported`.

- [ ] **2. Shared search support and prefilter selection.** Finish
  `src/util/{alphabet,determinize,escape,int,lazy,memchr,pool,primitives,
  sparse_set,syntax,unicode_data,utf8,wire}.rs` behavior and
  `src/util/prefilter/{mod,aho_corasick,byteset,memchr,memmem,teddy}.rs` as
  one cross-engine contract. Port vendor boundary/overflow, Unicode, storage
  reuse, candidate, false-positive, memory, and strategy-selection tests;
  verify bounded and overlapping candidate flow through dense, hybrid,
  PikeVM, backtracker, and Meta. Diagnose/replace generic Aho fallback where
  Rust's algorithm differs, including Teddy, or document a proven necessary
  divergence with performance evidence. **Gate:** shared utility and
  prefilter ledger rows have tested dispositions, and no remaining
  candidate/choice difference silently changes results or hot-path cost.

- [ ] **3. Thompson construction and NFA search engines.** Finish
  `src/nfa/thompson/{nfa,builder,compiler,literal_trie,range_trie,map,error,
  pikevm,backtrack}.rs` as a coherent NFA feature. Port Rust builder doctests,
  exact graph/state/limit/error queries, reverse construction, HIR/range
  cases, capture and memory contracts, and source-level private helpers.
  Run all Rust-admissible PikeVM and bounded-backtracker TOML modes through
  phase 1's runner, including caches, visited-bitset reuse, captures,
  overlapping, Unicode-empty, quit, and capacity/error precedence. **Gate:**
  their source/test rows are individually reconciled and both engines pass
  their applicable full vendor matrices, not only selected regressions.

- [ ] **4. Dense DFA construction, execution, and transforms.** Finish
  `src/dfa/{automaton,accel,dense,determinize,minimize,remapper,search,
  special,start}.rs` against Rust API, regression, and suite tests. Cover
  start/EOI and special states, byte classes, match/pattern metadata,
  forward/reverse/overlap, anchors, earliest and match-kind modes, limits and
  failure precedence. Run transformed-automaton adversarial cases through
  remap/minimize/truncate/swap/shuffle, checking transitions, starts, matches,
  accelerators, and serialized results. Assess Rust scratch-builder pooling
  against Crystal's direct-key construction without assuming either is faster.
  **Gate:** dense runtime and transform rows plus all applicable vendor dense
  suite modes pass with explicit exclusions and no unexplained state-map drift.

- [ ] **5. Vendor DFA wire compatibility, sparse DFA, and regex wrappers.**
  Port dense and sparse native/little/big-endian serialization and checked
  malformed-input behavior from `src/dfa/{dense,sparse,regex}.rs` and
  `tests/{dfa,gen,fuzz}/**`. Replay the checked-in `multi_pattern_v2` forward
  and reverse `.dfa` files and fuzz crash inputs as **Rust bytes**, not rebuilt
  Crystal DFAs. Bring sparse state queries, conversion, memory, and wire
  layout into parity or record the exact public incompatibility and necessity
  of dense-backed storage. Cover dense/sparse wrapper construction, reverse,
  iterators, multi-pattern/captures, and always-anchored semantics. **Gate:**
  vendored bytes and malformed cases have reproducible results, and generated
  test rows are not signed off by Crystal-only round trips.

- [ ] **6. One-pass DFA engine.** Finish `src/dfa/onepass.rs` and
  `tests/dfa/onepass/**`: source-level admission/rejection, transition and
  match-side epsilon/slot representation, table queries, limits, cache/reset,
  captures, and errors. Run every admissible case in vendor `default`,
  `no_byte_classes`, and `starts_for_each_pattern` modes through the shared
  runner, with the Rust non-anchored and UTF-8-empty exclusions/behavior.
  Compare admitted results with other engines on the same case IDs. **Gate:**
  the one-pass source/test ledger is reviewed and its full supported vendor
  matrix passes, beyond the existing 12-case anchored reader.

- [ ] **7. Meta strategy and complete facade behavior.** Finish
  `src/meta/{error,limited,literal,prefix,regex,reverse_inner,
  reverse_suffix,stopat,strategy,wrappers}.rs` and `tests/meta/**`. Recheck
  each strategy's Rust admission, name/diagnostic path, guards, ordered
  fallback, configured engine restrictions, capture/multi-pattern paths,
  cache/pool reset, memory, and error precedence. Run all admissible cases in
  the five vendor modes (`default`, `no_dfa`, `no_dfa_hybrid`,
  `no_dfa_hybrid_onepass`, `no_dfa_hybrid_onepass_backtrack`). **Gate:** every
  Meta source/test row is justified and all five full mode matrices pass;
  previous reverse-strategy spot checks remain regression evidence, not a
  substitute for this gate.

- [ ] **8. Cross-engine adversarial audit and vendor signoff.** Replay shared
  vendor case IDs across every engine/mode that Rust admits; classify each
  mismatch and engine-specific exclusion. Independently cover generated/fuzz
  families, malformed wire, transformed DFAs, bounds, Unicode, captures,
  quit errors, and public API examples. Review every source file (including
  no-row files), all 1,936 source rows, 220 test rows, and all intentional
  divergences for necessity and cost. Recheck the vendor submodule pin; if it
  changed, regenerate the generated manifests and repeat the affected audit.
  **Gate:** full Rust and Crystal quality gates pass, inventories are current,
  no unresolved behavior gap is hidden by a divergence label, and this file
  has no unchecked phase.
