# Regex-automata parity roadmap

## Contract and evidence

- Source of truth: the checked-in `vendor/regex/regex-automata/` at commit
  `72d650cb0a880a01ab6dc2137c0888e8f89740f7` (regex-automata 0.4.18).
  Do not substitute remembered Rust behavior or a newer upstream revision.
- Working source ledger: [rust_port_inventory.tsv](inventory/rust_port_inventory.tsv)
  (1,936 Rust API items: 1,276 `ported`, 369 `missing`, 105 `partial`, 181
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

## Where we are

- **Current focus:** phase 2f, shared search support utilities. Phase 2e
  ported the pinned Teddy selector/memory cases first, observed red tests,
  implemented the matching Rust algorithms, and passed local AArch64 and x86
  AVX2/SSSE3 CI runtime gates. The completed feature commit is
  `port: cross-target Teddy and strategy accounting`.
- **Next up:** 2f shared utilities; 3 Thompson NFA construction/search.
- **Status by area:** vendor fixture harness, scalar prefilter
  selection/candidate semantics, AArch64 unanchored packed Teddy, 2-500 needle
  Aho/anchored Teddy DFA, and >500-needle contiguous-NFA paths are complete.
  Phase 2e implements and verifies x86 SSSE3/slim AVX2/fat AVX2 dispatch,
  Rust's packed-plus-anchored-DFA allocation accounting, and dense/hybrid/
  PikeVM/backtracker/Meta consumption. Shared utilities and engine matrices
  beyond hybrid remain open in phases 2f and 3-8.
- **Scoping notes:** The pinned two-pattern AArch64 memory oracles are 2,537
  and 1,956 bytes, and the 65-pattern DFA oracle is 5,684 bytes. Rust's
  x86 slim AVX2 adds one verifier-ID copy. Aho/ByteSet now release original
  needle copies; ByteSet embeds its 256-byte table in the strategy object,
  while Teddy retains its packed verifier patterns. The added x86
  Actions gate requires AVX2 and exercises the >32-pattern fat and forced
  SSSE3 paths. Crystal cannot directly express the pinned SIMD intrinsics:
  Rust `aho-corasick` 1.1.4 `packed/teddy/{generic,vector}.rs` maps to
  Crystal `teddy_matcher.cr` plus `teddy_native.c`. The search performs one C
  FFI call, Rust-style vector nibble shuffles and set-bit candidate scanning,
  with no per-candidate heap allocation; the FFI boundary's measured cost is
  not established by this loaded host. Phase 2f owns a controlled x86 A/B
  throughput comparison against pinned Rust before any speed claim.
- **Last completed feature commit:** `port: cross-target Teddy and strategy
  accounting` (phase 2e; this commit).
- **Gates:** phase 2e focused Crystal prefilter 29/29 and full Crystal
  10,317/10,317 on AArch64. The [x86 AVX2/SSSE3 Actions workflow](https://github.com/dsisnero/regex-automata/actions/workflows/x86-teddy.yml)
  runs the same focused/full suites, format check, and no-codegen build;
  verify its run for the feature commit before advancing. Pinned aho-corasick
  1.1.4 Teddy tests 8/8 and regex-automata prefilter unit 5/5 and
  integration 7/7 (offline); ARM64/x86 C cross-compiles with `-Werror`,
  install, format, lint, parity, format-check, no-codegen, and diff-check pass.

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

Phase 1 closed with the shared vendor fixture reader
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

- [x] **2a. Scalar prefilter selection and candidate contract.** Port Rust's
  memchr{,2,3}, memmem, and large ByteSet choices with their fast/strategy-memory
  reporting, bounded find/prefix, and leftmost-first overlap behavior. Make
  the current Aho fallback observable, and drive the work with Rust prefilter
  examples and cross-engine pending-match tests; verify the selected path
  rather than inferring it from output alone. **Gate:** scalar/ByteSet choices
  have tested selection and candidate dispositions, with all multi-substring
  fallback differences explicitly queued for phase 2b.

- [x] **2b. AArch64 packed Teddy candidate search.** Port the pinned
  `aho-corasick` 1.1.4 SlimNeon admission, low-nibble prefix grouping,
  1–4-byte masks, eight-bucket verification, bounded SIMD windows, and the
  short-haystack Rabin–Karp path used by Rust's Teddy prefilter. Port its
  leftmost-first, binary, overlap, and offset-variation cases before code;
  exercise consumers so eligible unanchored searches do not silently run the
  generic failure-link matcher. A small native NEON packed-search kernel is
  justified because Crystal has no equivalent intrinsic; all matcher
  construction and short-path logic stay Crystal. **Gate:** on AArch64,
  eligible unanchored prefilters select and execute packed Teddy, with no
  false negatives or priority drift over bounded spans. Anchored DFA belongs
  to 2c; cross-target SIMD and complete strategy memory accounting to 2e.

  The necessary native boundary is explicit: Rust's
  `aho-corasick-1.1.4/src/packed/teddy/generic.rs` and `vector.rs` issue NEON
  intrinsics directly; Crystal's `teddy_matcher.cr` builds the same masks,
  buckets, and Rabin–Karp fallback, while `teddy_native.c` performs the
  vector shuffle/verify loop in one call per `find`. The 261-offset vendor
  matrix and bounded-span specs check observable equivalence. FFI overhead
  and throughput are not signed off on this loaded host and remain a
  controlled-measurement item for 2e.

- [x] **2c. Aho DFA selection and search.** Port the pinned `aho-corasick`
  1.1.4 DFA for the regex-automata wrapper's 2-500-needle Aho choice and
  Teddy's anchored prefix search, including byte classes, pre-multiplied
  transition table, leftmost-first priority, bounded and binary search, and
  anchored/unanchored starts. Port the named upstream cases before code and
  verify selected backends through consumers. See
  [feature-aho-dfa.md](feature-aho-dfa.md). **Gate:** eligible Aho and Teddy
  prefix searches no longer execute the generic failure-link matcher; Rust
  cases and candidate semantics pass with source and test rows reconciled.

  The pinned builder's leftmost-first prefix pruning, dead failure states,
  contiguous byte-class boundaries, and interleaved anchored/unanchored
  pre-multiplied transitions are present in `aho_dfa.cr`. Its search uses the
  first match in each state, as Rust's non-overlapping search does, and
  shuffles match states before ordinary states so non-matches avoid metadata
  loads. Crystal stores a `-1` dead sentinel instead of Rust's explicit DEAD
  and FAIL state IDs. This simplifies Crystal construction; both paths do one
  flat transition lookup and one match-state ID comparison per byte. Named upstream
  cases, binary/bounded spans, the 500/501 choice, and Teddy prefix verify
  observable candidate equivalence. Exact allocation reports and controlled
  throughput comparison remain phase 2e, with no performance signoff claimed
  on the loaded host.

- [x] **2d. Contiguous Aho NFA.** Port the pinned dependency's contiguous NFA
  for >500 needles, including its transition representation, anchored and
  unanchored starts, leftmost-first pruning, and memory report. Exercise the
  500/501 selection boundary and large adversarial needle sets through all
  prefilter consumers. **Gate:** no >500-needle hot path executes the generic
  hash-edge trie and Rust candidate cases pass with ledger evidence.

  `aho_contiguous_nfa.cr` follows `aho-corasick` 1.1.4's u32-packed dense,
  one-transition, and sparse states, byte classes, DEAD/FAIL sentinels,
  match-state ordering, both starts, failure traversal, and leftmost-first
  prefix pruning. The generic hash-edge matcher was removed. Named upstream
  leftmost/anchored cases, bounded binary 500/501 cases, and the pinned
  501-needle 2,772-byte memory oracle pass; dense, hybrid, PikeVM,
  backtracker, and Meta consume its candidates. The Crystal representation
  keeps mutable builder nodes separate from the final packed array, as Rust's
  builder does; the search hot path reads only the packed array and byte-class
  table. Phase 2e completed exact Aho DFA allocation accounting.

- [x] **2e. Teddy cross-target completion and strategy accounting.** Complete
  x86 SSSE3/AVX2 Teddy admission, packed search, runtime capability checks,
  exact strategy memory and retained-needle accounting for all prefilter
  choices. Recheck selection, false positives, and memory through dense,
  hybrid, PikeVM, backtracker, and Meta. **Gate:** no eligible hot path
  silently substitutes the generic failure-link matcher on supported targets;
  unavoidable divergences name both paths, necessity, observable equivalence,
  and static hot-path cost evidence, with noisy-host throughput claims deferred
  to the controlled comparison in 2f.

  Pinned `aho-corasick` 1.1.4 `packed/tests.rs` Teddy variation cases and
  forced SSSE3 selection run alongside the x86 fat-AVX2 boundary, bounded
  binary/duplicate cases, and an all-consumer regression. Exact AArch64
  Rust memory oracles (2,537/1,956/5,684 bytes) and Rust's packed storage
  formula are checked. The portable Crystal implementation uses a C SIMD
  bridge solely for unavailable intrinsics; the packed search itself follows
  Rust's vector masks, short-span Rabin-Karp, and set-bit verification. The
  bridge's one call per search is the only extra hot-path boundary, with no
  candidate allocation. Its measured throughput cost is deferred to 2f
  because the local machine is loaded; no no-slowdown claim is made here.

- [ ] **2f. Shared search support utilities.** Finish
  `src/util/{alphabet,determinize,escape,int,lazy,memchr,pool,primitives,
  sparse_set,syntax,unicode_data,utf8,wire}.rs` behavior. Port vendor
  boundary/overflow, Unicode, storage-reuse, and memory tests across their
  consumers. Audit the scalar memchr{,2,3}/memmem finder hot paths and retained
  needle ownership left partial by phase 2a against Rust's implementation;
  perform a controlled x86 A/B comparison of the Teddy C bridge against the
  pinned Rust implementation, and benchmark only under controlled load.
  **Gate:** every named utility file
  and its ledger rows have tested dispositions; no remaining structural
  difference silently changes results or hot-path cost.

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
