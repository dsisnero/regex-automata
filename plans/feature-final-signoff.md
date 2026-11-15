# Final vendor signoff (phase 8)

This is the existing final phase, pinned to `rust-lang/regex`
`72d650cb0a880a01ab6dc2137c0888e8f89740f7`. It adds no regex feature or phase.

- [x] Reconcile all source, test and file review rows against the pinned
  checkout. Record target-specific dispatch and layout differences.
- [x] Review shared search paths, scalar retention and dense scratch reuse.
- [x] Verify generated and vendor suites, malformed wire, transformed DFAs,
  bounds, Unicode, captures, quit behavior and public examples.
- [x] Measure the kept optimization paths on the controlled x86 runner.
- [x] Pass the Rust, Crystal, native oracle and inventory gates.

## Current evidence

Phase 7 is `8edddc8`. Only the user's two existing documentation changes were
present at resume. Vendor pin is unchanged. Fresh baseline logs are
`temp/phase8-baseline-{lint,parity,test}.log`; lint (133 files), all 23,382
specs and inventory gates pass. The native pinned suite also passes 204 unit,
60 integration and 459 documentation tests (two upstream ignores).

Dense and sparse native wire/endian/fuzz checks, the DFA wrapper oracle and
the one-pass oracle pass after the shared changes. A source-derived regression
also exposed repeated dense builder calls corrupting a previous result; the
builder now preserves returned tables. The generated nine-engine boundary and
capture matrix matched the pinned Rust output.

The first source-backed fix is the quadratic single-needle verifier in
`prefilter.cr`. The authoritative dependency is memchr **2.8.1**, recorded in
the vendor Cargo lock and available in the local Cargo source cache. DeepWiki
provided navigation but incorrectly inferred a resolved version from the
Cargo version requirement; only the locked source controls this port.

## Source-backed regressions and independent evidence

- `scripts/check_final_cross_engine.sh` generates 1,872 bounded cases across
  20 families and compares 16,848 native results through dense/minimized,
  sparse/minimized, hybrid, PikeVM, backtrack, one-pass and Meta. All results
  agree: pattern/end offsets, complete participating capture spans, admission,
  unsupported-anchor and quit errors. Done spans, UTF-8 splits, raw bytes,
  custom line terminators, earliest and both match kinds are included.
- `spec/support/byte_search_bounds.c` passes AddressSanitizer and
  UndefinedBehaviorSanitizer on the current AArch64 target. Exact-sized
  buffers exercise aligned/unaligned tails, both directions and packed pairs.
  The later x86 runner passed the sanitizer checks on its native target.
- `spec/final_shared_contract_spec.cr` and `spec/dfa_state_cache_spec.cr` exposed the standalone native-endian
  special-state overflow, strict empty match-slice validation, repeated dense
  builder ownership, eager extraction and string extraction splitting a code
  point. Each behavior correction has a failing-then-passing regression.
  `spec/support/final_shared_oracle.rs` independently confirms extraction
  string/byte differences and whole-match-before-group error order.
- `spec/interpolate_spec.cr` exposed `${+1}` being misclassified as a name.
  Both byte and string replacements now use Rust's unsigned decimal grammar;
  full-width numeric callbacks and overflow-to-name behavior are independently
  checked by the native shared oracle. Existing Int32 capture callbacks ignore
  unrepresentable numeric groups instead of treating them as names.
- `spec/memmem_finder_spec.cr` covers pinned suffix cases, exhaustive short
  binary words, 256 deterministic long periodic/near-periodic/binary fallback
  cases, and comparison-count bounds. Diagnostic counters compile out of
  production. The long fallback suite passes with diagnostics enabled.

## Representation adaptations reviewed in this phase

| Rust source | Crystal source | Necessity, equivalence and cost |
| --- | --- | --- |
| `util/captures.rs::extract{,_bytes}` | `captures.cr::extract_matches/extract_string` | Crystal has no const-generic return array or borrowed string view. Runtime count and owned Array preserve participating-group order and lazy requested-prefix consumption. String results copy their extracted bytes and check two UTF-8 endpoints; byte results borrow slices. Result work is O(requested groups + copied string bytes), with no full-group collection. |
| `util/captures.rs::GroupInfo::memory_usage` | `captures.cr::GroupInfo#memory_usage` | Crystal Array/Hash metadata cannot share Rust Arc/BTreeMap layout. The deterministic estimate counts name bytes, logical hash entries and actual optional slot width, excluding object headers and spare capacity. This is a metadata query, outside the per-byte search loop; exact Rust allocation thresholds are not asserted. |
| `dfa/special.rs::from_bytes` | `special.cr::Special.from_bytes`, `dense_wire.cr` | The optional standalone convenience helper returns an owned value or nil, versus Rust's private Result plus consumed count. The containing native DFA reader retains typed error handling and exact byte counts. Fixed validation/decoding is construction-only; there is no added search step. |
| `util/primitives.rs` and `dfa/onepass.rs` optional slots | `types.cr`, `onepass.cr`, `captures.cr` | Crystal optional Int32/NonMaxUsize slots occupy 16 bytes on the audited 64-bit Crystal 1.22.2 target, versus Rust's eight-byte Option niche. The previous one-pass note claiming equal width was corrected. No per-byte conversion array is introduced. |
| module/reexport and `macros.rs` files | `src/regex-automata.cr` and namespaces | All default engine/utility modules are included. Rust cfg/no-std packaging and disabled log/debug/trace macro expansion introduce no additional default runtime algorithm or search allocation. |

The source ledger has 1,740 ported items, 183 intentional divergences and
13 skipped entries. The test ledger has 210 ported tests, nine intentional
divergences and one skipped test. All 72 file reviews have a disposition.

## Measurement builds

CI compares the phase 7 baseline at `8edddc8`, the current Crystal build,
a scalar forward comparison build and pinned Rust. The initial experiment
unrolled both directions. The successful retention run tests the production
forward and reverse choices on the same workloads. Local harness runs default
to offline. CI builds the standalone Cargo manifests with exact dependency pins.

## Allocation experiments (no timing evidence)

Release binaries ran three independent `--alloc` processes, each probing 16
operations after warm-up/collection, using Crystal 1.22.2 on AArch64. These
are per-process GC byte counters and remain usable under competing host CPU
load; they are not timings or native allocator equivalence. Workload and raw
results are in `bench/final_signoff.cr` and the durable
[evidence table](evidence/phase8-allocations.tsv). Raw scratch files remain
under `temp/final-perf/*alloc*.tsv`.

| Dense construction candidate | Mean GC bytes/build | Decision |
| --- | ---: | --- |
| Phase-7 ordered-array keys (`8edddc8`) | 430,215 | Baseline |
| Initial byte-key/scratch port with class views | 559,377 | Rejected: 30% allocation regression |
| Stack Repr/ReprVec views | 441,584 | Still regressed |
| Direct writes into the existing header | 430,494 | Flat; insufficient on its own |
| Value-typed builder stages as in Rust | 396,939 | Kept. The later x86 run confirmed 7.7% less allocation on its build workload. |

The private borrowed views and three builder stages are now structs, matching
Rust's value wrappers. Their byte buffers retain the same owned/scratch
lifecycle; owned cached keys remain independent after clearing a probe.
Header writes borrow a checked four-byte Slice instead of allocating a new
buffer for each flag update. Existing state roundtrip/clone/priority and
builder reuse contracts pass (131 focused examples).

The same probe exposed `DFA#is_start_state?` falling back to materialized
Hash values on every ordinary byte, even when start specialization was off.
Pinned `dense.rs` uses only Special range predicates. A source-derived test
failed for specialization disabled; a second failed on raw ID 1 being
misclassified as quit. All five predicates now use Special directly, also
avoiding out-of-range accelerator indexing. The native shared oracle checks
the classification contract. On the 64 KiB workload, measured forward/reverse
search allocation fell from about 10,486,000 bytes/call to 17/3 bytes/call;
pooled/explicit-cache Meta measured 16/16 bytes/call versus 1,526/1,448. Small
residual counters are reported as observed, without an assertion of exact
zero allocation or a throughput claim.

Review also found the autogenerated Int32 constructor bypassing
`LazyStateID.new` checks: MAX+1 became a match-tagged ID instead of returning
the pinned overflow error. Raw construction now has a separate private
marker argument; checked construction accepts all integer widths through one
path, while explicit unchecked tagging remains four bytes. The regression
failed then passed; all 57 focused hybrid examples pass.

The prior complete Crystal run passed **23,401 examples**
(`temp/phase8-final-full-test.log`). The signed Input range, UTF-8 boundary,
quit Display and hybrid debug-assertion fixes pass all **53 focused specs**
and the independent Rust oracle. All **16,848** cross-engine results still
match. The full rerun passed **23,402 specs** (`temp/phase8-resume-full.log`).
Lint, compile, format, diff and inventory gates pass. The working API ledger
uses comma-separated file references so the current parity skill can verify
each cited file individually.

The file review checked hybrid cache eviction and directional UTF-8 retries,
paired-regex reverse search, Input/Span, automaton forwarding, Special wire
validation and both Aho-Corasick choices. On the search path, the offset-zero
UTF-8 check now uses the same byte predicate as other offsets. Quit Display
formats the byte when an exception is constructed. The hybrid reverse
pattern-ID check compiles in debug builds, as in pinned Rust. Crystal Input
accepts signed offsets and rejects negatives at construction of the search
span. Rust's unsigned offsets exclude those values by type.


## Finite construction budget

Both `dfa/dense.rs::Config::determinize_size_limit` doctests pass against
pinned Rust. For `\w{20}`, Rust rejects 700,000 bytes with both start modes
and 200,000 with anchored starts. It accepts 800,000 and 300,000 respectively
and reports a match. Crystal rejects all four limits with a typed construction
size error. With a 16,000,000-byte limit, Crystal builds and reports end offset
20 in both configurations. The Rust runner accounts for encoded states and
its reusable NFA stack. Crystal also retains a separate StateMeta closure representation and
uses a different scratch allocator. Copying Rust's estimated byte count would
ignore storage required by the Crystal builder. This is an observable budget
admission difference. The configured cap continues to constrain the estimated
auxiliary storage of whichever builder is in use. Once admitted, both
engines report the same observed match offsets. Callers using tight Rust
budgets may need to retune them for Crystal.

`dfa.cr::Builder#determinize_memory_usage` now adds metadata payload costs
as rows are appended, including specialized start copies. The check is O(1)
per insertion at finite limits, with one integer update per appended row and
no search cost. The four Crystal probe results are identical before and after
the change. The 73 focused state-cache, dense and transform specs pass, as do
lint and the inventory gates. All 23,402 specs pass with incremental accounting
(`temp/phase8-budget-full.log`).

## x86 retention decisions

Run 43686039721 passed the full Crystal suite, AVX2/SSE2/scalar bridge tests,
pinned native comparisons, and the benchmark correctness checks.
[Full measurements](evidence/phase8-x86-43686039721.md).

- Forward four-step DFA search went from 285 to 166 µs per 64 KiB workload,
  a 42% improvement. It is the default. Reverse unrolling went from 328 to
  432 µs, a 32% regression. The reverse loop remains scalar.
- The first two-byte forward kernel was 47–48% slower than phase 7.
  Three-byte performance was within 1%. Default x86 forward scans use the
  measured phase 7 libc strategy. Reverse scans continue to use the bridge.
- The packed-pair verifier for short needles was roughly 10× slower than
  phase 7 on the short workload. The x86 short path uses a libc scan for
  the ranked rare byte and verifies at most 32 bytes per candidate.
  Long and periodic workloads keep the Two-Way candidate path, which
  reduced this runner's 3.7–7.5 ms cases to about 2 µs.
- Teddy 2/16 remained about 3.8× slower and the 65-string case about 15%
  slower than pinned Rust. Phase 7 Crystal and the checkpoint were within
  1%. The x86 bridge's existing gap remains visible in the evidence.
- Dense build allocation fell from about 429,410 to 396,701 GC bytes per
  operation on the x86 workload. Pooled and explicit-cache Meta searches
  were each about 15× faster than phase 7 on this workload.

## Retained-path confirmation

Run [43692303102](https://github.com/dsisnero/regex-automata/actions/runs/43692303102)
passed both x86 jobs on `4a7e8e8`.
[Retained-path measurements](evidence/phase8-x86-43692303102.md).

- Byte 1–3 and short substring cases are within 1% of phase 7. The default
  x86 implementation uses libc forward byte scans. The short substring
  verifier scans for a ranked byte and compares at most 32 bytes per
  candidate, bounding verification work by a constant times haystack size.
  Other vector targets retain the packed short verifier, and all vector
  targets continue to use pair candidates for eligible long needles.
- Forward four-step search took 153.5 µs per 64 KiB versus 211.5 µs for
  scalar forward search, a 27% reduction. The scalar reverse comparison
  stayed within 1% across the two current builds. The four-step forward
  loop adds no search allocations on this workload.
- Dense build used 396,694 GC bytes/op versus 429,618 in phase 7 (7.7% less).
  Pooled Meta search took 49.8 ns versus 785.8 ns in phase 7 and 17.5 ns
  in pinned Rust. Teddy 2/16 took about 2.5 times as long as Rust. The
  65-needle row measures the Aho-Corasick fallback despite its historical
  label. That row was 17% slower than phase 7 and 15% slower than Rust on
  this run. The matcher implementations are unchanged from phase 7.
  These measurements describe each workload and do not isolate individual
  system or function costs.

## Dense transform representation and cost

Rust's `dfa/{remapper,minimize,dense}.rs` swaps dense rows in place and
repairs IDs. Crystal's `dfa.cr` exposes the existing materialized `states`
array, so its transforms rebuild rows and synchronize that graph with the
flat table. The retained graph adds one State per row and one StateID per
logical transition alongside the flat backing table. `minimize.cr` uses
array partitions and a Boolean source mark array for splitter membership.
The reverse relation includes one entry per logical transition, including
EOI. It allocates marks and split arrays during refinement. Rebuilding
takes a pass over the new rows and start references. These costs are limited
to construction and storage. Search uses the flat table and requires no
additional branch for the materialized graph. The native wire oracles,
transformed fixtures and minimized cross-engine matrix verify search
results, starts, match metadata, transition and accelerator behavior.

## Signoff gates

- Crystal `make test` on the retained-path commit passes all 23,402 specs.
- Pinned Rust passes 204 unit tests, 60 integration tests and 459 doctests
  with two upstream ignores. Dense and sparse wire and fuzz, DFA wrapper,
  one-pass and cross-engine oracles pass.
- The x86 run passes the native bounds checks, AVX2/SSE2/scalar variants,
  default and scalar forward comparison builds, and the controlled benchmark.
- Install, format, lint, inventory, type-check and diff checks pass.

Phase 8 closes with the documented budget admission and dispatch differences.
The two successful x86 runs record the remaining throughput differences from
pinned Rust. The signoff branch holds the tested implementation and evidence.
