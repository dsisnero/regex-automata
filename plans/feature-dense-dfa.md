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
- Per mode, the pinned 1,194 cases yield 1,150 selected after the substring
  `expensive` blacklist (44 excluded). Of these, 46 non-ASCII haystacks with
  Unicode word looks are Rust DFA skips, leaving 1,104 eligible cases: five
  expected compile errors and 1,099 compiled cases. Every compiled case gets
  `is_match` and `find`; 77 overlapping cases additionally exercise `which`
  through `Automaton#try_which_overlapping_matches`. No selected case uses
  unsupported leftmost-longest. The seven mode tests each cover 25 TOML
  groups; the case trace records exact IDs such as
  `regression/reverse-suffix-start-of-match-failure-030`,
  `regression/reverse-suffix-all-no-early-matches-010`, and `unicode/class9`.
- Audit `automaton.rs`, `search.rs`, `start.rs`, `special.rs`, and the dense
  execution/determinization portions of `dense.rs` and `determinize.rs`.
  Preserve Rust's forward/reverse/overlap, EOI, quit, anchored, earliest,
  match-kind, and error-precedence behavior. Review the direct-key builder
  against Rust scratch reuse without benchmark claims on a loaded host.
- The `dfa/search.rs` audit found another execution gap: Rust's non-overlapping
  forward and reverse loops use accelerator bytes in start, match, and other
  accelerated states; Crystal previously did this only for overlapping
  searches. Those branches now use the existing accelerator helpers, with a
  focused accelerated-versus-unaccelerated `Input` spec. Verify the full vendor
  matrix after this change. This is source-level optimization parity, not a
  timing claim.
- Current red-green findings: `crlf/start-end-non-empty` and
  `crlf/start-no-split-adjacent-cr` require Rust's half-CRLF start and EOI
  logic; `set/basic61-leftmost-first` requires first-match priority rather
  than sorted IDs; `regression/reverse-suffix-start-of-match-failure-030`
  requires preserving ordered NFA subsets; `bytes/invalid-utf8-anchor-100`
  exposed a Crystal-only contextual-start transition rewrite that Rust does
  not perform. The minimized-mode
  `regression/reverse-suffix-all-no-early-matches-010` showed that Crystal's
  `Automaton#try_search_fwd_once` returned a pending match as soon as it
  entered a start state, whereas Rust `dfa/search.rs::find_fwd` keeps scanning
  without a prefilter; removing that non-Rust early return fixed the case
  without changing minimization. `minimized_no_byte_class/unicode/class9`
  exposed an empty-predecessor-set loop in the Crystal minimizer: Rust's
  Hopcroft refinement skips empty incoming sets. The focused case timed out
  before the fix and passes after it. The full verbose gate then caught
  `dfa/api.rs::unicode_word_implicitly_works`: the conditional closure
  shortcut must derive `look_need` from the ordered epsilon closure (as Rust's
  `add_nfa_states` does), not just the seed NFA set. Its focused spec passed
  after the correction. A source audit of `dfa/search.rs::find_fwd` exposed
  quit-error precedence with a pending match; a focused Rust-derived spec was
  red before changing `Automaton#try_search_fwd_once` to return the quit error
  unconditionally, then green. Keep these exact case IDs in the runner. Verify the
  ordered-subset cache's construction cost and its full suite behavior before
  claiming runtime parity; the loaded host's elapsed time is not throughput
  evidence. The Rust wrapper explicitly clears a forward prefilter for its
  reverse DFA, so an explicit `nil` override is part of this feature.
- Do not close 4b on the initial default mode: execute all seven dense modes
  with the overlapping find/which expansion. Rust
  `regex_test::TestRunner::blacklist("expensive")` filters any full case name
  containing that substring, including `fowler/repetition` cases, not only
  the `expensive` TOML group; the initial runner erroneously included those
  pathological cases and its full gate was stopped after more than an hour.
  Run specs with `--fail-fast --error-trace -v` and `DENSE_SUITE_TRACE=1` to
  identify the currently executing case; the verbose spec label alone shows
  only the last completed group. The minimized no-byte-class Unicode group
  passed `class9` but needs longer than a 240-second bound for its many cases;
  elapsed time on this loaded host is not a benchmark.
  Focused seven-mode `anchored` and `bytes` groups are green. An earlier full
  `--fail-fast --error-trace -v` run completed the first five modes and
  reached `minimized_default/unicode/class-emoji4` before its 30-minute
  safety bound. Isolated `minimized_default` and
  `minimized_no_byte_class` runs each passed 25 group examples. The first
  unbounded `make test` on the post-accelerator source ran 16,277 examples
  and found two failures outside the new vendor matrix. The curated
  `unminimized_prefilter` spec had manually supplied `"abcd"` as a prefilter
  for patterns where it is unsound; pinned `dense.rs::Config::prefilter`
  explicitly warns that such prefilters can return incorrect results. Both
  curated dense/sparse prefilter specs now derive their prefilter from the
  patterns' HIRs, as pinned `tests/dfa/suite.rs` does. The older
  `quit_after_match_spec.cr` expected a pending match to suppress a later quit
  error, contrary to pinned `dfa/search.rs::find_fwd` and `eoi_fwd`; its
  assertions now require the Rust error, and the Crystal-only slice search
  also returns that error. The focused 18-example regression set passes;
  the final unfiltered full gate passes. The
  `util/determinize/mod.rs::next` audit also found that Rust recomputes epsilon
  closure only when a byte satisfies a newly needed look assertion. Crystal
  had recomputed for every state with any look, which Rust warns may change
  priority after unconditional epsilon states are omitted. The predicate is
  now ported exactly; the focused 147-example DFA set and seven-mode vendor
  regression group (7/7 group examples) pass.
- The `dfa/automaton.rs` audit found that the public
  `try_which_overlapping_matches(Input, PatternSet)` default method was absent
  even though Crystal's suite manually reproduced its loop. The pinned Rust
  example first failed to compile as a Crystal spec, then passed after porting
  the method. Additional specs cover caller-owned set reuse, too-small sets,
  and `earliest`; the suite's `which` expansion now calls this API directly and
  all seven focused overlapping groups pass. The final unfiltered gate
  includes this API surface.
- Rust `dense.rs::BuildError::nfa` also wraps syntax/NFA compilation errors
  rather than returning an NFA error directly, and its
  `is_size_limit_exceeded` stays false even when the underlying NFA hit its
  own size limit. A focused Crystal spec failed on the escaping NFA error;
  the DFA builder now preserves the NFA source in `BuildError#nfa_source` and
  applies Rust's classification. The focused 150-example DFA set and pinned
  Rust `dfa::api` integration tests (5/5 offline) pass.
- Phase 4b signoff: the final unfiltered Crystal suite passes 16,280/16,280,
  including all seven dense modes and the added API/error specs. `make install`,
  `make format`, `make lint`, `make parity`, `git diff --check`, Crystal
  format-check, and no-codegen build pass. Runtime inventory dispositions are
  updated; transform, wire, and scratch/cache-key performance review remains
  assigned to phases 4c, 5, and 8 respectively. No loaded-host benchmark
  claim is made.

## 4c: transforms

- Audit `accel.rs`, `minimize.rs`, `remapper.rs`, and dense state-shuffling
  paths. Port adversarial remap/minimize/truncate/swap/shuffle checks over
  transitions, starts, match IDs, accelerators, and serialized results.
- Mark file-level rows only after the private algorithm review. Dense wire
  compatibility and sparse/wrapper suite modes remain phase 5.
