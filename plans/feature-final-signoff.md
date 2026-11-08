# Final vendor signoff (phase 8)

This is the existing final phase, pinned to `rust-lang/regex`
`72d650cb0a880a01ab6dc2137c0888e8f89740f7`. It adds no regex feature or phase.

- [ ] Reconcile the 19 partial API rows, one partial test, pending/private file
  reviews and existing divergence dispositions against pinned source/evidence.
- [ ] Close the named shared algorithm/cost gaps: scalar prefilter retention,
  combined byte/reverse scans, memchr 2.8.1 Finder dispatch/Two-Way fallback,
  dense determinizer scratch/key reuse, and DFA loop/transform costs.
- [ ] Replay admitted vendor IDs and bounded generated/adversarial families
  across engines; verify native wire, malformed/fuzz, transformed, bounded,
  Unicode/capture/quit behavior and public examples with independent Rust.
- [ ] Obtain controlled performance/allocation evidence for kept optimization
  changes, including the existing x86 Teddy bridge and Meta pool comparisons.
  This busy host is not a timing oracle. Use the existing x86 workflow route
  after the patch is reviewable; do not interpret loaded-host timings.
- [ ] Run required native/Crystal/inventory gates, update the roadmap and make
  one atomic final-phase commit. No final signoff while required evidence or
  known material gaps remain open.

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
  x86 runtime evidence is still pending; a successful cross-compile is not
  runtime proof.
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

Five API rows remain partial. Dense Runner memory accounts for encoded keys
and scratch payload but still estimates the Crystal metadata and scans its
state rows for each finite-limit check. Matching the Rust byte thresholds
remains open. Combined memchr2/3 find and memmem Finder new/find are implemented,
with x86 runtime validation and controlled measurements outstanding. Scratch
get/put now have source, ownership and allocation evidence in the API ledger.

## Measurement checkpoint and approval

Local branch `codex/final-vendor-signoff` contains a measurement checkpoint
(initially `65f21f9`, subsequently amended with review fixes). It is **not
final phase closure**. The
controlled workflow compares baseline `8edddc8`, current scalar/default loops,
experimental `-Ddfa_unrolled_search`, and pinned Rust. All 20 benchmark result
checks agree locally, without collecting timings. Separate `--alloc` probes are recorded below; this loaded host remains
unsuitable for timings.

Automatic approval review rejected publishing the checkpoint to the public
`dsisnero/regex-automata` branch because explicit payload/destination approval
was missing. A user approval question is pending. No root-repo push or remote
CI run occurred. Do not retry or work around that rejection without approval.
The final inventory/source review, controlled evidence and final quality gates
remain required; there is no phase 9.

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
| Value-typed builder stages as in Rust | 396,939 | Keep for 7.7% allocation reduction; controlled timing still required |

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
match. The full rerun is logged in `temp/phase8-resume-full.log`.
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
