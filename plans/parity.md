# Regex-automata parity roadmap

## Contract and evidence

- Source of truth: the checked-in `vendor/regex/regex-automata/` at commit
  `72d650cb0a880a01ab6dc2137c0888e8f89740f7` (regex-automata 0.4.18).
  Do not substitute remembered Rust behavior or a newer upstream revision.
- Working source ledger: [rust_port_inventory.tsv](inventory/rust_port_inventory.tsv)
  (1,936 Rust API items: 1,739 `ported`, 0 `missing`, 5 `partial`, 179
  `intentional_divergence`, 13 `skipped`). Test ledger:
  [rust_test_parity.tsv](inventory/rust_test_parity.tsv) (220 rows: 210
  `ported`, 0 `partial`, 9 `intentional_divergence`, 1 `skipped`). These are **review
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
  mutex as an `intentional_divergence` were returned to `partial` in phase 1.
  Phase 2f3 now ports the pool owner/sharding path; its measured throughput
  remains unproven on this loaded host. Native dense/sparse wire cases
  closed in phase 5; broader cross-engine adversarial and controlled
  performance signoff remain phase 8 work.

## Where we are

- **Current focus:** phase 8, the final existing cross-engine/shared-utility
  audit and controlled performance signoff. Phase 7 Meta is complete:
  [feature evidence](feature-meta.md), all 275 API rows and 11 file reviews,
  five-mode vendor matrix and full gates are closed. The bounded
  [final signoff checklist](feature-final-signoff.md) tracks phase 8. Current
  source work ports the memchr 2.8.1 substring fallback and combined byte
  scans, and removes redundant scalar needle storage. Baseline logs are
  `temp/phase8-baseline-{lint,parity,test}.log`; all baseline gates pass (23,382
  specs). Native Rust unit/integration/doc suites and dense/sparse wire, DFA
  wrapper and one-pass oracles pass. All 16,848 generated nine-engine
  results agree with pinned Rust, including the experimental unrolled build.
  Decoder, capture extraction, replacement-parser and state-classification gaps
  are fixed and documented in the final checklist. Final inventories and
  controlled measurements remain open. Branch `codex/final-vendor-signoff`
  is published on GitHub. All 23,402 local specs passed at `a273a0f`.
  The [first x86 run](https://github.com/dsisnero/regex-automata/actions/runs/43682798950)
  passed the Teddy suite and AVX2/SSE2/scalar bridge checks. Cargo's missing
  vendor workspace lockfile stopped the measurement job. Commit `589748a`
  lets CI build the standalone harnesses with their exact dependency pins.
  The next run found missing executable modes on both harness scripts.
  Commit `ae3a2b0` records those modes, and the
  [rerun](https://github.com/dsisnero/regex-automata/actions/runs/43686039721)
  passed both x86 jobs. The [measurements](evidence/phase8-x86-43686039721.md)
  support the four-step forward loop and scalar reverse loop. The x86
  two-byte and short-needle misses regressed in the experimental native
  kernels. The current candidate selects libc scans for those cases and
  retains Two-Way plus packed-pair candidates for long needles.
  All 23,402 local specs passed after the incremental budget-accounting
  change. Focused checks pass with the resulting retention changes.
- **Next up:** validate the retained paths in the updated x86 harness and
  run the full gates. Exact finite-budget admission still differs from
  pinned Rust, as recorded in the final signoff checklist.
- **Dependency correction:** grouped dot translation now preserves the syntax
  terminator through `regex-syntax` commit `1623e24`. The dedicated pushed
  branch and review draft are recorded in the [Meta plan](feature-meta.md).
  Its full 21,832-spec shard gate passes; no temporary-path dependency remains.
- **Status by area:** vendor fixture harness, scalar prefilter
  selection/candidate semantics, AArch64 unanchored packed Teddy, 2-500 needle
  Aho/anchored Teddy DFA, and >500-needle contiguous-NFA paths are complete.
  Phase 2e implements and verifies x86 SSSE3/slim AVX2/fat AVX2 dispatch,
  Rust's packed-plus-anchored-DFA allocation accounting, and dense/hybrid/
  PikeVM/backtracker/Meta consumption. Phase 2f1 closes alphabet/escape/UTF-8,
  Unicode table, and primitive-ID source-file reviews. Phase 2f2 closes the
  five numeric/syntax/determinization/sparse-set files. Remaining shared
  utilities and engine matrices beyond hybrid remain open in phase 2f4
  and 3-8.
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
  not established by this loaded host. Phase 8 owns a controlled x86 A/B
  throughput comparison against pinned Rust before any speed claim. The
  Crystal-only signature/quitset byte-class reducers now relabel byte 255's
  group last at construction; the search lookup remains one table access.
- **Thompson representation divergence and cost:** Rust
  `src/nfa/thompson/{builder,nfa}.rs` memory usage includes fixed Rust enum/
  `Inner` sizes and variable heap allocations; Crystal
  `src/regex/automata/nfa.cr` reports a Crystal-layout estimate instead.
  Byte-identical counts are impossible across the two object models; size
  limits still reject graph growth and the Unicode-versus-ASCII memory
  ordering is tested. Queries are off the search hot path. Rust
  `nfa.rs::look_set_prefix_all` is deliberately commented out as incorrect;
  the former Crystal method and intersection computation were removed, so
  no unsupported hot-path work remains. Rust's retained `ByteClassSet` now
  maps to Crystal's retained `ByteClassSet`, with the derived `ByteClasses`
  computed once at NFA construction. Crystal returns a deep copy from the
  `byte_class_set` getter because it has no immutable-reference return type;
  hybrid DFA construction adds quit-byte boundaries to that copy, mirroring
  Rust's clone-and-extend path. This is construction-only work, with no added
  search lookup.
- **Dense builder extension and cost:** Rust
  `src/dfa/dense.rs::Builder::build_from_nfa` always derives classes from the
  NFA or singletons; Crystal `src/regex/automata/dfa.cr::Builder#initialize`
  additionally accepts caller-supplied `ByteClasses` for existing Crystal
  callers. Standard `build`/`build_from_nfa` now follow Rust; the extension
  bypasses derivation only when explicitly supplied. It adds no search-time
  branch or lookup. No speedup claim is inferred from the smaller alphabet on
  this loaded host.
- **Dense transform representation and cost:** Rust
  `src/dfa/{remapper,minimize,dense}.rs` uses in-place row swaps followed by
  swap-cycle ID repair; Crystal `src/regex/automata/{dfa,minimize}.cr` rebuilds
  a final-order transition table and materialized state array together because
  both representations are retained. The transform tests cover equivalent
  transition, EOI, start, match and accelerator IDs, while the seven-mode
  vendor suite checks search behavior. This is construction-only work with no
  extra search-time branch; its allocation and construction-time cost are not
  established on this loaded host and remain a phase 8 comparison.
- **Pool/lazy divergence and cost:** Rust `src/util/lazy.rs` alloc path maps
  to Crystal `src/regex/automata/lazy.cr` with one acquire load and CAS
  publication; Crystal's GC-safe wrapper allocates only on a factory run.
  Rust `src/util/pool.rs` owner/sharded path maps to Crystal
  `src/regex/automata/pool.cr`: Meta's owner `Pool#with` path performs thread
  identity lookup plus atomic load/store, without a mutex or guard allocation;
  misses use one atomic try-lock for pop and at most ten for return. Padded
  shard objects isolate lock words because Crystal cannot express Rust's
  `repr(align(64))` exactly. Crystal GC cannot deterministically invoke
  `PoolGuard::drop`: direct Meta searches use `ensure`, iterators return caches
  on exhaustion/`each` or explicit `#close`, and raw guards require `#put`.
  Abandoning a raw guard/iterator without closing can leave its owner cache
  unavailable for the pool's lifetime. This is a lifecycle divergence, not a
  search-result divergence. No throughput claim is made on this loaded host; phase 8's
  controlled comparison should include pooled Meta searches.
- **Last completed feature commit:** phase 7 `port: Meta strategy and facade
  parity` (`8edddc8`). Prior phase 6 is `6e45c59`; wrapper phase 5c
  is `887355b`, sparse phase 5b `ebf762c`, dense phase 5a `853c6c6`.
- **Gates:** **23,382/23,382 full Crystal specs** and 15,453 affected-engine
  focused specs pass. The Meta matrix runs 1,186 admissible cases per mode,
  5,930 examples total, including build errors and overlapping pattern sets.
  Pinned Rust passes 68 Meta units, all five integration modes and 77 doctests.
  The grouped-terminator dependency regression also passes all 21,832 shard
  specs and downstream contracts. Install, format, lint, parity, whitespace/
  format checks and no-codegen build pass. These are correctness gates; no
  loaded-host throughput claim is made.

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

- [x] **2f1. Shared byte alphabet, Unicode data, and identifier values.**
  Review `src/util/{alphabet,escape,primitives,unicode_data,utf8}.rs` against
  the Crystal value layer and its DFA/look consumers. Port source-defined
  byte/EOI debug output, complete ASCII word-byte and invalid UTF-8 boundaries,
  checked identifier limits and errors, and the generated Unicode table
  contract. **Gate:** all five files have file-level dispositions, relevant
  rows/specs are reconciled, and direct constructors cannot silently create
  invalid IDs. The pinned `ByteClasses::alphabet_len` uses byte 255's class;
  malformed maps are rejected against that bound. Crystal's signature/quitset
  builders can discover byte 255's equivalence group early, so they relabel
  that group last at construction without changing any search-path lookup.
  Rust's `SmallIndex::new` Result is exposed as Crystal
  `try_new`; Crystal `.new` raises on invalid input, and `new_unchecked`
  remains explicit. Rust `NonMaxUsize`'s `usize::MAX` sentinel is unreachable
  for Crystal's Int32 slice offsets; the Crystal value is Int32, rejects
  negative offsets, and accepts `Int32::MAX`. Capture-slot construction has
  one signed check instead of Rust's one sentinel check and no allocation.
  The pinned `regex-automata` and `regex-syntax` Rust `perl_word.rs` files are
  byte-identical; all 796 Unicode 16.0 ranges equal the Crystal regex-syntax
  table, so reusing its binary-search predicate avoids duplicated data and
  does not add a lookup to the look-around hot path.

- [x] **2f2. Numeric casts, syntax, determinization, and sparse-set
  support.** Finish `src/util/{int,syntax,determinize/{mod,state},sparse_set}.rs`
  as one construction-time state/limit layer. Port vendor overflow, parser
  configuration, state encoding, and storage-reuse cases before fixes; audit
  direct Crystal casts and builder behavior across dense, hybrid, and NFA
  consumers. **Gate:** each file has a tested disposition, including private
  algorithms and the necessity/cost of any structural difference.

  Rust's `SparseSet::contains` indexes `sparse[id]` and panics for an
  out-of-capacity ID; Crystal now does likewise. Both `iter` and block `each`
  traverse the dense prefix without allocating a sliced array on the
  determinization/PikeVM path. The Debug tuple and StateID order are tested.
  The pinned `(?:\b|%)+` on `z%` counterexample still yields `[0,0]` then
  `[1,1]` through Hybrid and the separate dense builder, preserving union
  priority during conditional closure.
  Five offline Rust state property tests, deterministic Crystal state-ID/varint
  boundaries and byte oracles, and builder reuse cover state encoding. A
  red-green backing-buffer capacity check corrected Hybrid's scratch-memory
  report and removed per-ID capacity bookkeeping from the construction path.

  Rust `util/int.rs` centralizes private checked/truncating casts; Crystal
  uses checked native conversions and masks/shifts at the corresponding call
  sites rather than a wrapper trait, with no additional search-path step.
  Rust `Config::apply_ast`/`apply_hir` in `util/syntax.rs` map to Crystal
  `Config#apply` in `syntax.cr` because the Crystal regex-syntax dependency
  exposes one parser builder; all options reach its AST parser and HIR
  translator, without search-path cost. Rust's `u32` nest limit is now stored
  as `UInt32`; applying values above `Int32::MAX` clamps only the dependency's
  signed parser argument, which cannot represent a realizable greater AST
  depth, at construction time. Rust `State::borrow` maps to Crystal's
  byte-view lookup in `determinize_state.cr`; the candidate view is not copied
  before hashing and frozen states still copy the bytes. Rust's dense NFA
  state transition variant is not yet present in the Crystal NFA; phase 3 owns
  that engine-level addition, while this shared transition path is reviewed.

- [x] **2f3. Lazy initialization and pooled cache ownership.** Complete
  `src/util/{lazy,pool}.rs` as the shared cache-lifecycle feature. Port the
  vendor owner/distinct-guard/cross-thread cases first, check automatic
  release and panic/exception behavior, and preserve Rust's low-contention
  fast path wherever Crystal permits it. **Gate:** reuse and concurrency
  behavior are proven through consumers; any mutex/ownership divergence has
  observable-equivalence and hot-path evidence.

  The alloc-backed Lazy uses atomic publication and permits competing
  factories; nil results and a raising factory are covered. Pool capacity is
  a shard count, not a cache-retention cap. Vendor `thread_owner_optimization`,
  `thread_owner_distinct`, `thread_owner_sync`, and `thread_owner_send_drop`
  cases are ported; deterministic contention specs cover transient discards
  and failed returns. Meta direct searches reuse owner cache without a guard
  allocation; iterators hold a guard across steps and release at exhaustion,
  scoped enumeration, or explicit close. Rust's deterministic `Drop` for
  abandoned objects has no Crystal equivalent; the scoped API and limitation
  are recorded above. Meta's impossible-input checks now precede pool checkout
  as in Rust; complete Meta strategy and capture matrices remain phase 7.

- [x] **2f4a. Native wire helpers.** Finish `src/util/wire.rs` separately from
  the independent scalar-search performance feature. Port its five unit tests
  and malformed-buffer boundaries for labels, checked arithmetic, alignment,
  endian/version fields, integer and ID reads, and LE/BE writers. The Rust
  reader's unusual `first_nul + padding_len(first_nul)` consumed length is
  preserved, with a red-green regression at the four-byte label boundary.
  Crystal stores typed IDs directly instead of Rust's zero-copy u32-to-ID
  casts, so no extra search-path conversion is introduced. Crystal aligned
  allocation reserves at most seven extra bytes and is off the search path.
  Native dense/sparse DFA byte layouts and their malformed-input suites remain
  phase 5. **Gate:** source-file review and nearest Rust tests are reconciled;
  focused and full Crystal gates pass.

- [x] **2f4b. Scalar-search correctness and source audit.** Review pinned
  `src/util/memchr.rs`, `src/util/prefilter/{memchr,memmem,byteset}.rs`, and
  the accelerator call sites. Source-characterization tests went red then green
  for Rust's `get(span.start)` byte-prefix behavior on empty spans and for
  out-of-range accelerator offsets. Bounded binary/overlap candidates and a
  memchr3 path through dense, hybrid, PikeVM, backtracker, and Meta pass.
  Crystal now limits libc `memchr` probes to the requested span. Its 2/3-byte
  prefilter still makes two/three bounded libc scans instead of Rust's one
  combined SIMD scan; accelerator 2/3 search remains a scalar loop; memmem
  still verifies first-byte probes instead of using pinned memchr 2.8.1's
  packed-pair/Two-Way Finder. Retained scalar needle copies for Meta are also
  not signed off. These are **unresolved performance/retention gaps**, not
  accepted intentional divergences; phase 8 owns implementation and controlled
  measurement before final parity signoff. **Gate:** result/error contracts and
  source/test rows are reconciled, with no throughput claim on this loaded host.

- [x] **3a. PikeVM vendor matrix and source review.** Run the pinned
  `tests/nfa/thompson/pikevm/suite.rs` default and prefilter modes over every
  Rust-admissible case in phase 1's 25-group TOML runner, including `is_match`,
  `find`, captures, earliest and overlapping pattern sets. Preserve Rust's
  unsupported-match-kind and overlapping-captures skips. Port remaining
  `src/nfa/thompson/pikevm.rs` source contracts, including cache reuse and
  Unicode-empty behavior. **Gate:** full applicable vendor matrix passes and
  PikeVM source/test ledger rows are individually reconciled.

  Rust's `nexts_overlapping` rejects an empty match at a non-UTF-8 boundary
  using the NFA's `has_empty` flag and the current offset, with no capture
  slots; Crystal previously read absent slots and admitted the match. The
  pinned `utf8/empty-utf8yes-bounds-overlapping` case went red then green.
  The special ASCII/Unicode start/end/half word look kinds now reach the
  shared LookMatcher instead of raising. The cache now owns one reusable
  closure frame stack, uses the active sparse set for visited states, and
  traverses straight-line epsilon edges without push/pop, matching Rust's
  hot-path choices. There is no measured throughput claim on this loaded host.
  The missing `State::Dense` representation and PikeVM terminal/transition
  branches are explicitly `partial` in the source ledger and belong to 3c;
  current compiler-generated states and the full PikeVM TOML matrix pass.

- [x] **3b. Bounded-backtracker vendor matrix and source review.** Run the
  pinned `tests/nfa/thompson/backtrack/suite.rs` default, prefilter and minimum
  visited-capacity modes over every Rust-admissible TOML case, preserving its
  exact blacklist and search/match-kind exclusions. Port outstanding
  `src/nfa/thompson/backtrack.rs` contracts for visited reuse, captures,
  capacity and error precedence. **Gate:** full applicable vendor matrix
  passes and backtracker source/test rows are individually reconciled. The
  vendor matrix found missing special word-look dispatch, now ported. Source
  review also removed full capture-scratch sizing on non-empty-match paths,
  matching Rust's allocation condition. The only identified state-transition
  gap, Rust `State::Dense`, is recorded `partial` and belongs to 3c because
  the Crystal Thompson representation does not yet produce it.

- [x] **3c1. Thompson Dense representation and engine consumption.** Port
  `src/nfa/thompson/nfa.rs`'s `DenseTransitions` byte/unit/haystack/iteration
  contract and `State::Dense` accounting, plus its PikeVM/backtracker closure,
  stepping, and overlapping paths. Port Rust's zero-capture `PikeVM::is_match`
  search and conditional capture-scratch sizing. **Gate:** source-derived
  direct-state specs exercise absent/EOI transitions, memory and byte-class
  accounting, and both engines; prior vendor matrices remain green. The
  pinned compiler's sparse-to-dense conversion in `Inner::into_nfa` is
  commented out after unhelpful ad-hoc benchmarking, so this phase does not
  invent Dense generation or claim a performance gain. No upstream Rust test
  directly constructs a Dense state; direct-state Crystal specs are branch
  characterizations from the pinned source, not fixture parity claims. Rust's
  `Box<[StateID]>` in `nfa.rs` maps to Crystal's `Array(StateID)` in `nfa.cr`
  because Crystal has no equivalent boxed-slice value type; both keep 256
  constant-time indexed targets and the same `StateID::ZERO` sentinel.
  `Dense#iter` materializes transitions in Crystal rather than returning a
  borrowing iterator; only construction/inspection paths use it, and the
  pinned compiler never emits Dense states, so normal search hot paths incur
  no added work.

- [x] **3c2. Thompson NFA, builder, and error contracts.** Reconcile
  `src/nfa/thompson/{nfa,builder,error}.rs` graph/state/limit/error queries,
  starts and pattern IDs, reverse unions, captures, byte classes, memory,
  remapping, malformed-builder behavior, Debug formatting, and pinned doctests.
  **Gate:** all three source/test/file ledgers have evidence-backed dispositions
  and the complete code gates pass. Source/test/file review and full gates pass. The
  compiler-only `Match.next` placeholder audit is explicitly assigned to 3c3.

- [x] **3c3a. Thompson UTF-8 tries and bounded maps**
  ([feature plan](feature-thompson-compiler.md)). Finish
  `src/nfa/thompson/{literal_trie,range_trie,map}.rs`: literal priority chunks,
  forward/reverse trie compilation, range splitting, lexicographic iteration,
  reusable state/scratch storage, direct-mapped UTF-8 cache collision and
  version behavior, Debug contracts, and both pinned native trie tests.
  Include the empty-pattern compiler configuration regression found during
  integration review. **Gate:** these three source/test/file ledgers are
  individually reconciled with direct pinned evidence and full code gates pass.

- [x] **3c3b. Thompson HIR compiler algorithms**
  ([feature plan](feature-thompson-compiler.md)). Finish
  `src/nfa/thompson/compiler.rs`: HIR and UTF-8 class lowering, reverse
  construction, literal/range trie and bounded-map integration, private
  helpers, and pinned compiler tests/doctests. Audit the Crystal compiler's
  `Match.next` patchable placeholder against Rust lowering; remove its extra
  builder goto path if possible or document necessity, observable equivalence,
  and construction cost. Reuse compiler-owned trie/UTF-8 scratch storage as
  Rust does. **Gate:** compiler source/test/file rows are individually
  reconciled against exact pinned Rust evidence. All 74 source rows, 19 native
  tests, and the file-level review are closed; full gates pass (16,101 Crystal
  specs). The Crystal-only `Match.next` edge is removed.

- [x] **4a. Dense DFA alphabet-compressed construction.** Follow pinned
  `dense.rs::Builder::build_from_nfa` and `Config::overwrite`: clone the NFA's
  retained `ByteClassSet`, add quit-byte boundaries, preserve singleton mode,
  and honor explicit `false` overrides. Cover the mixed quit/non-quit source
  regression, class map, transition-row indexing, accelerator implications,
  and search behavior with tests before implementation. Keep this phase's
  source ledger notes and [dense DFA subplan](feature-dense-dfa.md) current.
  **Gate:** focused and full correctness gates pass; no claim that the entire
  dense runtime, transform, or vendor suite matrix is done. The byte-class
  spec failed before the fix, and the focused suite then passed 74/74. The
  full suite passed 16,103/16,103 and pinned Rust DFA API tests passed 5/5
  offline.

- [x] **4b. Dense DFA runtime and vendor suite.** Audit pinned
  `src/dfa/{automaton,dense,determinize,search,special,start}.rs` for start/EOI
  and special states, match/pattern metadata, forward/reverse/overlap,
  anchors, earliest/match-kind modes, limits, and error precedence. Port and
  run all applicable `tests/dfa/{api,regression,suite}.rs` dense modes via the
  shared fixture harness, with exact Rust exclusions. Assess Rust scratch-
  builder reuse against Crystal's direct-key construction without an
  unsupported speed claim. See the [dense DFA subplan](feature-dense-dfa.md).
  **Gate:** runtime source/test/file rows and full dense suite modes pass.

- [x] **4c. Dense DFA transforms.** Audit pinned
  `src/dfa/{accel,dense,minimize,remapper,special}.rs` and port transformed-
  automaton adversarial tests for remap/minimize/truncate/swap/shuffle,
  checking transitions, starts, matches, accelerators, and serialized results.
  Reconcile affected source/test/file rows and documented divergences. See the
  [dense DFA subplan](feature-dense-dfa.md). **Gate:** no unexplained state-map
  drift; full correctness gates pass. Wire compatibility itself remains 5.

- [x] **5a. Dense native wire compatibility.** Port dense v2 wire readers,
  writers, validation, generated Rust byte fixtures, dense fuzz regressions,
  and the full native serialization vendor mode. See the
  [DFA wire feature plan](feature-dfa-wire.md). **Gate:** actual Rust bytes
  and cross-language writes pass; dense wire source/test rows are reconciled.

- [x] **5b. Sparse native storage and wire compatibility.** Port packed
  byte-offset states, dense conversion, queries, memory, starts, match and
  accelerator data, wire formats, exact generated bytes, sparse fuzz inputs,
  and all supported sparse vendor modes. See the
  [DFA wire feature plan](feature-dfa-wire.md). **Gate:** sparse source/test
  rows and file review close with native byte and search evidence.

- [x] **5c. DFA regex wrappers.** Review dense/sparse construction, reverse,
  iterators, multi-pattern matches, errors, and always-anchored semantics
  against `src/dfa/regex.rs` and its tests. See the
  [DFA wire feature plan](feature-dfa-wire.md). **Gate:** wrapper source/test
  rows have evidence-backed dispositions and applicable vendor modes pass.

- [x] **6. One-pass DFA engine.** Finish `src/dfa/onepass.rs` and
  `tests/dfa/onepass/**`: source-level admission/rejection, transition and
  match-side epsilon/slot representation, table queries, limits, cache/reset,
  captures, and errors. Run every admissible case in vendor `default`,
  `no_byte_classes`, and `starts_for_each_pattern` modes through the shared
  runner, with the Rust non-anchored and UTF-8-empty exclusions/behavior.
  Compare admitted results with other engines on the same case IDs. See the
  [one-pass feature plan](feature-onepass-dfa.md). **Gate:**
  the one-pass source/test ledger is reviewed and its full supported vendor
  matrix passes, beyond the existing 12-case anchored reader.

- [x] **7. Meta strategy and complete facade behavior.** Finish
  `src/meta/{error,limited,literal,prefix,regex,reverse_inner,
  reverse_suffix,stopat,strategy,wrappers}.rs` and `tests/meta/**`. Recheck
  each strategy's Rust admission, name/diagnostic path, guards, ordered
  fallback, configured engine restrictions, capture/multi-pattern paths,
  cache/pool reset, memory, and error precedence. Run all admissible cases in
  the five vendor modes (`default`, `no_dfa`, `no_dfa_hybrid`,
  `no_dfa_hybrid_onepass`, `no_dfa_hybrid_onepass_backtrack`). **Gate:** every
  Meta source/test row is justified and all five full mode matrices pass;
  previous reverse-strategy spot checks remain regression evidence, not a
  substitute for this gate. See the [bounded Meta checklist](feature-meta.md).

- [ ] **8. Cross-engine adversarial audit and vendor signoff.** Replay shared
  vendor case IDs across every engine/mode that Rust admits; classify each
  mismatch and engine-specific exclusion. Independently cover generated/fuzz
  families, malformed wire, transformed DFAs, bounds, Unicode, captures,
  quit errors, and public API examples. Review every source file (including
  no-row files), all 1,936 source rows, 220 test rows, and all intentional
  divergences for necessity and cost. Close phase 2f4b's performance/retention
  gaps: port or justify the pinned memchr2/3 combined scan, memchr 2.8.1
  memmem Finder dispatch and accelerator reverse scans; avoid retained scalar
  needle copies where Meta can preserve its literal mapping; compare x86 Teddy
  C bridge and pooled Meta searches against pinned Rust under controlled load.
  For dense DFA construction/search, compare `src/dfa/determinize.rs` scratch
  `StateBuilder` reuse and byte-key cache with Crystal's ordered-array keys in
  `src/regex/automata/dfa.cr`, then port the reusable scratch path if it lowers
  construction allocation without priority drift. Review Rust's four-step
  unrolled `src/dfa/search.rs` loops against Crystal's scalar
  `src/regex/automata/automaton.cr` loops and port or justify only with
  controlled hot-path evidence; these are open optimizations, not accepted
  intentional divergences or speed claims on this loaded host.
  The current Crystal memmem verifier can take O(haystack × needle) work on
  repeated first-byte candidates, unlike Rust's Two-Way fallback; treat that
  as an unresolved algorithmic risk, not merely a missing benchmark.
  Do not run or interpret benchmarks while competing process load is high.
  Recheck the vendor submodule pin; if it
  changed, regenerate the generated manifests and repeat the affected audit.
  **Gate:** full Rust and Crystal quality gates pass, inventories are current,
  no unresolved behavior gap is hidden by a divergence label, and this file
  has no unchecked phase.
