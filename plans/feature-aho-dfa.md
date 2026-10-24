# Phase 2c: Aho DFA selection and search

Pinned sources: `vendor/regex/regex-automata/src/util/prefilter/aho_corasick.rs`
and `aho-corasick` 1.1.4 in the vendored `Cargo.lock`. Read the cached
dependency's `src/{dfa,nfa/noncontiguous,util/alphabet,tests}.rs` at that
exact version. The wrapper chooses a DFA for at most 500 needles and a
contiguous NFA above 500; the latter is phase 2d. Teddy uses an anchored DFA
for prefix searches, even when its unanchored search is packed.

## Red-green sequence

1. Port named nonempty-pattern cases from `LEFTMOST`, `LEFTMOST_FIRST`,
   `ANCHORED_LEFTMOST`, and `ANCHORED_LEFTMOST_FIRST` in dependency `tests.rs`.
   Pad with inert literals where needed to force the wrapper's Aho choice.
   Add backend-selection and bounded/binary-span assertions; prove red on the
   existing generic matcher before implementing the DFA.
2. Build the pinned DFA's byte-equivalence classes and power-of-two stride;
   compile failure transitions into a flat, pre-multiplied transition table.
   Keep the dependency's leftmost-first match priority and both search starts.
3. Route 2-500-needle Aho searches and Teddy anchored prefix search to the
   DFA. Preserve the Rust wrapper's `start_kind(Both)`, disabled prefilter,
   and leftmost-first Aho match kind for both regex match kinds.
4. Run focused Crystal and pinned Rust cases, test affected consumers, and
   reconcile the Aho/DFA source and test ledger rows. Document any remaining
   structural divergence without calling it parity merely because output
   tests pass.

## Boundary

This phase does not claim the >500-needle contiguous NFA, x86 packed Teddy,
or exact whole-strategy memory reports. Those are phases 2d and 2e. Do not
silently use the DFA for >500 needles or the old trie for a supported DFA
choice. Do not use loaded-host timing as throughput evidence.

## Completion evidence

The `aho-corasick` 1.1.4 cases `leftmost300/310/340/350/360`,
`leftfirst000/020/100/110/300/330/400`, and anchored counterparts were
ported with inert needles to reach the regex-automata wrapper's Aho choice.
They were red on the absent DFA backend and green after implementation.
`spec/prefilter_spec.cr` also checks binary bounds, the 500/501 choice, and
Teddy's anchored DFA; `spec/hybrid_source_audit_spec.cr` drives the selected
DFA through a hybrid consumer. The pinned dependency's
`search_leftmost_first::dfa_start_both_no_prefilter` and
`search_leftmost_first_anchored_dfa_start_both` tests pass.
