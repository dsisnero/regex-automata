# Architecture

The public entrypoint is [`src/regex-automata.cr`](../src/regex-automata.cr).
The implementation lives under [`src/regex/automata/`](../src/regex/automata/)
and follows the pinned Rust crate's engine boundaries:

1. `syntax.cr` and `hir_compiler.cr` adapt `regex-syntax` HIR into the
   Thompson NFA in `nfa.cr`.
2. `pikevm.cr` and `backtrack.cr` search that NFA directly.
3. `determinize.cr`, `dfa.cr`, and `sparse.cr` construct and search eager DFAs;
   `onepass.cr` handles eligible capture patterns.
4. `hybrid.cr` builds DFA states lazily; `meta.cr` selects and coordinates
   available strategies.
5. `search.cr`, `prefilter.cr`, `captures.cr`, `look.cr`, `wire.cr`, and other
   modules supply shared search, storage, and serialization behavior.

The Rust source is pinned under `vendor/regex/regex-automata/`. This page is a
map, not a parity claim: see [the roadmap](../plans/parity.md) and
[testing](testing.md) for current evidence and open engine gates.

Dense DFAs use a flat transition table with premultiplied StateIDs. Sparse
DFAs use packed byte-range states with byte-offset StateIDs and packed start
IDs; conversion does not retain a dense DFA. Both execute Input searches
through the shared Automaton interface. Dense native wire handling lives in
`dense_wire.cr`; sparse state and wire handling live together in `sparse.cr`.
The [wire feature plan](../plans/feature-dfa-wire.md) records the pinned byte
fixtures, interoperability checks, representation costs, and remaining work.

One-pass DFAs use flat 64-bit rows with inline match metadata and explicit
capture/look bits. A retained NFA supplies group and look metadata; searches
execute the compiled table with separate transition scratch and result slots.
The [one-pass plan](../plans/feature-onepass-dfa.md) records exact Rust fixture
shapes, admission decisions, capture regressions and representation costs.
