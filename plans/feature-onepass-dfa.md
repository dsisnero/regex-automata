# One-pass DFA engine (phase 6)

Source: `vendor/regex/regex-automata/src/dfa/onepass.rs` and
`tests/dfa/onepass/{regression,suite}.rs`, pinned to regex-automata 0.4.18,
`rust-lang/regex` commit `72d650cb0a880a01ab6dc2137c0888e8f89740f7`.

## Scope and current evidence

The complete public engine and its private construction/search algorithms are
reviewed, including all 123 source rows. Its supporting remapper's 13 rows are
also reviewed. The existing unit/regression ports remain in
`spec/dfa_onepass_spec.cr`; new source characterizations are in
`spec/onepass_contract_spec.cr`, and the full fixture matrix is in
`spec/onepass_vendor_suite_spec.cr`.

Baseline: lint/parity and all **16,429** Crystal specs pass. The first new
source-derived run failed all nine tests: singleton stride, payload memory,
stale optional captures, match/transition scratch separation, inherently
anchored low-level input, done-input precedence, incremental size limits,
explicit Dense NFA states, and Thompson overwrite. Missing clones and
fallible capture-marker preservation also went red before implementation.
The retained-workspace probes also verify Rust raw state counts (seven for
`a`, five for `^`) via its derived Compiler Debug, without editing vendor code.
The old special-case binary-dot classification was checked directly in Rust
and corrected to its actual NFA error.

The final focused gate passes **1,547** examples, including affected Thompson
compiler contracts and exact graph fixtures. Pinned Rust passes eight one-pass
unit tests, five one-pass integration tests (three modes and two regressions),
and 23 doctests offline. The existing 10-case dense and 18-case sparse
wire consumers also pass after the prefix-allocation fix.

The first full run passed 17,432 examples and exposed one stale Crystal-only
raw-state assertion; source inspection plus the Rust workspace probe established
its corrected count. The anchored-prefix path then went red on the matching
Rust count before its fix. The final unfiltered Crystal gate passes
**17,434/17,434**, recorded in
`temp/phase6-full-test-final.log`. Install, formatting, lint, parity,
whitespace/format checks and no-codegen build pass. Phase 6 is complete.

## Construction and representation

`src/regex/automata/onepass.cr` now stores flat `Array(UInt64)` rows.
The high 21 transition bits hold the raw state ID, bit 42 records match-wins
priority, and the low 42 bits hold 32 explicit-slot bits plus ten look bits.
The alphabet-length column stores a 22-bit pattern ID and the same epsilon
payload. An all-ones pattern field means no match. Row stride includes this
column, so disabling byte classes gives alphabet 256 and stride 512.

Admission follows Rust's ordered DFS, including ByteRange, Sparse and Dense
NFA states. A reusable SparseSet detects ambiguous epsilon paths and clears
in constant time; the stack is reused per row. Unequal packed transitions or
multiple match paths reject the pattern. Look availability and supported-bit
checks precede pattern/slot limits, and each new row checks payload size
before further graph exploration. The pinned guards use 32 explicit slots,
pattern limit `0x3FFFFF`, and a greater-than `2^21` state check. Tests exercise
all 32 slot bits and ordinary/size-limited construction; allocating millions
of states solely to hit the hard state boundary is not part of this gate.

Matching rows are swapped toward the tail in Rust's descending order. An
inverse row-origin map repairs consuming targets and starts once, preserving
priority/epsilon bits. Raw state indexes remain unmultiplied; the source
remapper's OnePass adapter likewise uses an identity index map. The private
trait and cycle-following adapter are inlined into this engine's known row
representation. This uses two temporary index arrays during construction,
with no search-time remap lookup. Construction scratch is released afterward.

The Unicode fixture `anchored/word-boundary-unicode-01` initially exposed a
319-versus-318 state mismatch. Rust `compiler.rs::compile/c_at_least` compiles
the AnyByte unanchored prefix through `c_byte_class`, allocating its patchable
end before its consuming state. Crystal's
`hir_compiler.cr::build_unanchored_prefix_placeholder` had omitted that end.
The pre-finalization target IDs therefore changed bounded UTF-8 cache hash
collisions: Rust duplicates a state that Crystal reused. Preserving the end
allocation restores the pinned cache behavior and exact 319-state result.
The anchored path also retains Rust's initial `c_empty` placeholder before
compiling the pattern. The temporary epsilons are removed during NFA
finalization and add no search transition. A failing vendor shape test and
anchored raw-state count preceded these prerequisite fixes. Existing private
compiler counts were corrected from six/four to Rust's observed seven/five;
the literal test also explicitly requires exactly one terminal Match.

## Search, slots and ownership

Each byte reads one class-mapped packed word. The match-tail comparison,
match-wins/earliest return, conditional looks, explicit transition slots and
final-position match follow the pinned order. A match copies transition
scratch to caller slots before applying match-side epsilons to the result;
match handling never changes transition scratch. Every active scratch slot
is cleared between searches, fixing stale optional groups.

Done input returns before scratch/slot mutation or anchor validation.
Low-level unanchored input is accepted when the NFA is inherently anchored;
unsupported ordinary/per-pattern modes retain Rust's error ordering.
Fallible captures updates its pattern marker only after a successful slot
search, preserving the previous marker when an error propagates. Caller
buffers of any length are supported, including partial, oversized and zero
slots. UTF-8 empty matches inside a code point are filtered after matching.
Single-pattern implicit scratch and find use a stack pair; missing implicit
slots for multiple patterns use an array, as Rust does.

Language adaptations and costs:

- Rust borrows/shared-owns its NFA and uses value configuration. Crystal
  retains an NFA reference, returns a scalar config snapshot, and clones
  table/start storage for DFA copies. Builder and cache clones copy mutable
  configuration/scratch independently. Source NFAs must remain immutable
  after construction, as with the other Crystal engines. Config getter/copy
  work is outside the byte loop.
- Crystal keeps the existing `Int32?` capture representation and also accepts
  `NonMaxUsize?`, directly over Array or Slice buffers. Stack Slice views
  borrow stable array storage for the duration of a call; searches never
  resize those arrays. No conversion array or per-byte heap object is used.
  The phase 8 layout audit corrected the earlier eight-byte claim: on Crystal
  1.22.2 on this 64-bit host, both `Int32?` and `NonMaxUsize?` occupy 16 bytes;
  Rust's `Option<NonMaxUsize>` occupies eight. Thus Crystal scratch uses twice
  the slot payload at this target, without an extra per-byte allocation.
  Cache reports payload length times the
  Crystal element size, excluding object headers/unused capacity.
- Rust Input is borrowed/value-owned; Crystal's Input is a class, so the
  convenience APIs clone its settings to anchor/force earliest without
  mutating caller state. This remains a per-call object allocation, outside
  the byte loop. Low-level APIs use the supplied Input directly.
- Rust size limits are usize; Crystal accepts its signed integer size range
  through Int64. Actual payload arithmetic is Int64; limits beyond Int32 and
  explicit removal are tested. Array indexing and existing engine offsets
  remain Crystal Int32. This is the port's shared numeric model, not support
  for Rust's larger theoretical unsigned address space.
- Rust full-graph Debug formatting and its private sparse formatting iterator
  are replaced by concise Crystal state/pattern/payload inspection and normal
  scalar inspection. Error messages preserve Rust Display wording. These
  diagnostic differences have no matching or hot-path work.
- The public DFA delegates packed storage to a private Admission object,
  keeping the existing Crystal engine interface and packed operations together.
  Its fixed class fields/headers and empty construction containers add overhead
  beyond Rust's single DFA value. Transition lookup crosses that private helper
  boundary once per byte; compiler inlining/indirection cost is unmeasured.
  No additional heap object is created by a transition.
- Crystal Array capacity/GC and fixed object headers differ from Rust Vec.
  DFA memory_usage follows Rust's table-plus-start payload formula and
  excludes the retained NFA. All admitted fixture counts agree on this host.
  Controlled construction/allocation/throughput signoff remains phase 8;
  timings on this loaded host are not speed evidence.

## Full vendor matrix and reproducibility

`scripts/check_onepass.sh` independently regenerates
`spec/fixtures/onepass_suite.tsv` with the pinned Rust crate and regex-test
reader, then requires exact equality. The source-characterization checks run
in `spec/support/onepass_oracle.rs` before generating the rows. No vendor
files or expectations are modified.

Each mode (`default`, `no_byte_classes`, `starts_for_each_pattern`) selects
**328** anchored cases with supported match kind, from all 25 loaded groups.
Exactly **120** compile and **208** reject as NotOnePass. Crystal must agree
with each recorded decision; it cannot silently skip its own build failures.
Every admitted case matches Rust's states/alphabet/stride/payload memory and
fixture results. The three selection-count examples plus 984 case examples
make **987** vendor specs.

Per mode, all 120 admitted cases run is_match. The 111 leftmost and one
earliest cases also run find/captures iteration and compare spans with PikeVM
on the same NFA/Input/case IDs. The eight overlapping cases run only is_match,
matching Rust's explicit exclusion of overlapping find/captures. The full
PikeVM vendor matrix independently checks their existence results too.
Unanchored and leftmost-longest fixtures are excluded by Rust's configure
policy, not reclassified as successful tests. The expensive group is loaded;
there is no added one-pass blacklist.

Admitted cases per mode by group: anchored 12, crlf 1, fowler/basic 82, iter 3,
line-terminator 2, misc 2, no-unicode 1, regression 1, utf8 16. Other selected
cases are required rejection decisions. This replaces the earlier anchored
12-case reader as signoff evidence.

```bash
crystal spec spec/onepass_contract_spec.cr spec/onepass_vendor_suite_spec.cr \
  spec/dfa_onepass_spec.cr
bash scripts/check_onepass.sh
CARGO_TARGET_DIR="$PWD/temp/rust-target" cargo test --offline \
  --manifest-path vendor/regex/regex-automata/Cargo.toml --lib dfa::onepass::tests
CARGO_TARGET_DIR="$PWD/temp/rust-target" cargo test --offline \
  --manifest-path vendor/regex/regex-automata/Cargo.toml --test integration dfa::onepass
CARGO_TARGET_DIR="$PWD/temp/rust-target" cargo test --offline \
  --manifest-path vendor/regex/regex-automata/Cargo.toml --doc dfa::onepass
```

The next feature is phase 7 Meta strategy/facade behavior and its five-mode
vendor matrix. Resume from plans/parity.md and the AGENTS.md gate checklist.
