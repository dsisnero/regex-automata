# Dense DFA phase 4 scope

Source of truth: pinned `vendor/regex/regex-automata/src/dfa/` and
`tests/dfa/` at `72d650cb0a880a01ab6dc2137c0888e8f89740f7`.

## 4a: alphabet-compressed construction

- Rust `dense.rs::Builder::build_from_nfa` derives byte classes from a clone
  of the retained Thompson NFA `ByteClassSet`, adding quit-byte boundaries;
  `byte_classes(false)` uses singleton classes. Verify default, singleton,
  and mixed quit/non-quit maps and search outcomes. The pinned source comment
  gives the mixed-class regression; it is not a standalone vendor test.
- Rust `dense.rs::Config::overwrite` preserves an explicitly set `false`
  (`Option::Some(false)`), including acceleration, minimization, per-pattern
  starts, byte classes, Unicode word boundaries, and specialized starts.
- Compacted state rows are indexed by class, not raw byte. Check the
  materialized transition view and acceleration candidates against the
  compressed alphabet. Keep custom caller-supplied class handling separate;
  it is a Crystal API extension, not Rust `Builder::build_from_nfa`.

## 4b: execution and suite

- Port the full `tests/dfa/api.rs` dense behavior and all applicable dense
  `tests/dfa/suite.rs` modes: default, prefilter, specialized starts, no byte
  classes, NFA shrink, minimized default, minimized no-byte-class. Use the
  shared 1,194-case fixture reader and record selected case IDs, expansion
  counts, and Rust skip rules; curated examples do not close suite rows.
- Audit `automaton.rs`, `search.rs`, `start.rs`, `special.rs`, and the dense
  execution/determinization portions of `dense.rs` and `determinize.rs`.
  Preserve Rust's forward/reverse/overlap, EOI, quit, anchored, earliest,
  match-kind, and error-precedence behavior. Review the direct-key builder
  against Rust scratch reuse without benchmark claims on a loaded host.

## 4c: transforms

- Audit `accel.rs`, `minimize.rs`, `remapper.rs`, and dense state-shuffling
  paths. Port adversarial remap/minimize/truncate/swap/shuffle checks over
  transitions, starts, match IDs, accelerators, and serialized results.
- Mark file-level rows only after the private algorithm review. Dense wire
  compatibility and sparse/wrapper suite modes remain phase 5.
