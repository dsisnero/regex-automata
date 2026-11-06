# Meta strategy and facade (phase 7)

Scope: the existing `src/meta/` surface at regex-automata 0.4.18,
`rust-lang/regex` commit `72d650cb0a880a01ab6dc2137c0888e8f89740f7`.
This is one feature commit. The existing phase 8 remains the final audit and
shared optimization/performance signoff; this work adds no regex functionality.

## Bounded completion checklist

- [x] Public facade, configuration, build/error precedence, ownership, cloning,
  queries, explicit caches and iterator/split behavior: 103 regex and 15 error
  source rows reviewed.
- [x] Wrappers, Core/Pre/reverse strategy selection, admission limits, retries,
  capture reruns, scratch lifecycle and private algorithms: remaining 157 rows
  and all 11 Meta files reviewed.
- [x] Five existing vendor modes through the shared TOML reader: 5,930 examples
  pass. Preserve the expanded-name blacklist, compilation errors, overlapping
  pattern sets and unsupported overlapping captures.
- [x] Required repository gates pass: **23,382 full Crystal specs**, 15,453
  focused specs, install/format/lint/parity, whitespace/format checks and the
  no-codegen build. Closed in one atomic phase 7 commit.

## Source-backed changes

- Use actual `WhichCaptures::None` in the NFA and suppress offset-bearing
  facade APIs while retaining existence and overlapping-pattern queries.
- Retain union minimum/maximum lengths for Rust's impossible-input guards.
  Early returns leave caller slots unchanged; capture searches reset the
  pattern marker. Literal and reverse fast paths write only supplied implicit
  slots, including a single supplied start slot, and retain slots on a miss.
- Use canonical anchored reverse `Input` searches instead of slicing the
  haystack. Exhausted spans now terminate correctly and surrounding context is
  preserved. Fix the shared reverse DFA loop to return immediately at a dead
  state, as `src/dfa/search.rs` does, rather than taking EOI from its predecessor.
- Rerun reverse-hit captures through Core's OnePass/backtracker/PikeVM nofail
  order. Preserve a literal strategy's prefix behavior for every anchored mode.
- Keep parser and search terminators independent, including captured/scoped
  groups after the pinned dependency correction below; parse every AST before any
  HIR translation, retain typed syntax/NFA causes and stop narrowing the
  configured one-pass limit to Int32.
- Clone Regex with shared compiled engines and a fresh pool. Deep-clone mutable
  Meta/PikeVM/backtracker/hybrid scratch, sparse sets and state-builder buffers;
  OnePass already supplies its deep cache clone. Config/Builder copies retain
  value configuration semantics. Derived Rust clones are reviewed even though
  discovery does not produce method rows for derives.
- Keep literal reset a complete no-op, including its lazy PikeVM factory.
  Retain unused scratch and Rust's missing optional-cache reset failure. Do not
  silently repair the pinned cache capture-layout behavior when switching to
  a regex with different group metadata.
- Default pool capacity uses the cached available-CPU count, with Rust's
  fallback of eight for failed/nonpositive discovery. Config retains explicit
  zero; the Pool constructor coerces it to one.

## Verification evidence

- Shared fixtures: 1,194 source cases, 1,186 admitted per mode, including five
  compilation errors and 77 overlapping cases. Eight names are excluded by
  Rust's `earliest/` blacklist after appending API suffixes; this includes
  `anchored/greedy-earliest/is_match`. No fixture assertions were weakened.
  The initial runner missed suffix expansion and incorrectly selected that
  case; its backtracker result agrees with Rust and required no engine fix.
- `spec/meta_vendor_suite_spec.cr` executes existence, nonoverlapping find and
  capture APIs, or overlapping PatternSet queries, for the same five modes as
  `tests/meta/suite.rs`. Results come directly from the vendor TOML data; no
  new oracle corpus is introduced.
- Eighteen source-derived facade/cache/clone contracts and all affected Meta,
  pool, PikeVM, backtracker, hybrid, one-pass, sparse-set, determinize-state and
  Automaton checks pass: **15,453 focused specs**.
- Native pinned Rust passes **68 Meta unit tests, five integration tests and
  77 doctests**, using `cargo test --offline --manifest-path
  vendor/regex/regex-automata/Cargo.toml` with respectively `meta:: --lib`,
  `--test integration meta::`, and `--doc meta::`. Build targets stay under
  `temp/rust-target`.
- Direct Rust characterization confirms AST error precedence, independent
  syntax terminators, capture-disabled offsets, wide one-pass limits, the
  literal invalid-pattern anchoring behavior, retained slots on reverse
  misses and the optional-cache reset panic. Three older Crystal-only
  clear-on-miss assertions were corrected to the actual Rust contract;
  `search_captures` still clears its pattern marker.
- Baseline: 17,434 full specs, lint and parity pass. Current logs are
  `temp/phase7-{focused,final-test,lint,parity,install,build}.log` and
  `temp/phase7-rust-{unit,integration,doc,audit}.log`. The final full run was
  restarted after the CPU fallback and dependency corrections; an interrupted partial run is
  not a completion gate.

The CPU failure injection is reproducible by running a separate Crystal program
that requires `src/regex-automata`, reopens `System.cpu_count` to return `-1`,
and asserts `Meta::Regex.config.get_pool_capacity == 8`. It failed before the
fallback correction and passes afterward. Run it in a separate process so its
replacement cannot affect the shared suite's CPU count or cached Lazy value.

## Dependency regression and upstream review draft

The scoped translator snapshot in the installed `regex-syntax` dependency
silently reset a custom line terminator: with `X` configured, `.` correctly
excluded X but `(.)` excluded newline instead. The pinned Rust translator
retains its terminator while changing only group flags. This is an actual
supported-option mismatch, rather than added project functionality.

The fix carries one `@line_terminator` field into child translators. It was
prepared from the previously pinned `077d107` in `temp/regex-syntax`, with a
failing-before exact-interval test covering captured, noncapturing, scoped-flag
and nested groups. All **21,832 shard specs**, formatting and 68-file lint pass;
the host's 18 contract specs verify `X=false, newline=true` for those forms.
The host now pins **1623e24e374171bcc165e7ca7e82f5a9fd5336db** from the
[pushed patch branch](https://github.com/dsisnero/regex-syntax/tree/codex/preserve-group-line-terminator).
There is no ignored `lib/` patch or temporary-path dependency to preserve.

Upstream PR draft, awaiting review (no PR has been created):

> **Title:** Preserve custom line terminators in group translator snapshots.
>
> `ParserBuilder#line_terminator('X')` correctly lowers `.`, but a grouped dot
> was lowered using the default newline terminator. Carry the configured
> terminator through `Translator#with_modified_flags`, matching pinned Rust
> `hir/translate.rs`. Add exact interval regressions for four group forms.
> Validation: 21,832 Crystal specs, format/lint, and consuming Meta contracts.

## Language adaptations and costs

- Rust `meta/regex.rs::RegexInfo` retains shared HIR `Properties`; Crystal
  `meta.cr::Regex` stores the scalar config, anchor/min/max/static-capture and
  property-memory summaries needed after construction. This avoids sharing
  the dependency's mutable property objects with caller-supplied HIR and
  preserves snapshot queries. Unused metadata is released; searches use
  scalar fields. Reported allocation sizes remain the port's representation
  estimates, with the shared memory-accounting review still in phase 8.
- Rust's private `meta/{strategy,wrappers}.rs` trait/wrapper objects map to
  typed optional-engine fields and inlined dispatch in `meta.cr`. Internal
  `Strategy::name`/Debug strings are omitted rather than exported solely for
  tests; test-only field probes verify the exact selection. Dispatch adds
  fixed strategy-field checks per call, without per-byte string/trait work.
  Phase 8's controlled Meta comparison remains the performance signoff.
- Rust borrowed/value `Input` settings map to owned Crystal Input snapshots;
  compiled engines/NFAs are shared by reference and must remain immutable.
  Regex clones allocate a new pool and cache clones duplicate mutable scratch.
  Input snapshots allocate per call rather than copying a Rust stack value;
  nothing here establishes equal throughput on this loaded host.
- Rust syntax-error enums and `Error::source` map to typed Crystal exceptions
  and `Exception#cause` in `meta_error.cr`. Display messages, classification,
  pattern IDs and limits agree; exception inspection/backtraces use Crystal's
  formatting. Error cloning shares immutable message/error payload references.
- Rust usize limits/offsets map to the port's Int64 limits, UInt64 capacities
  and Int32 indices/offsets. The wide one-pass limit is preserved. Existing
  `Int32?` capture APIs bridge to `NonMaxUsize?` buffers at wrapper boundaries;
  those bridges allocate/copy O(slot count) per search, outside byte loops.
  This is an existing shared capture representation cost, not a claim of Rust
  allocation parity; phase 8's cross-engine cost audit must account for it.
- The legacy limit-first `splitn` overload remains available alongside Rust's
  input-first order. Both delegate to the same implementation; there is no
  extra search work. `size_hint` uses Crystal's tuple/optional-value model.

No new regex feature or phase is authorized by this checklist. The next work is the existing phase 8 in `parity.md`.
