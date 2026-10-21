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
