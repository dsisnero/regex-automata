# Thompson compiler feature group

Source of truth: `vendor/regex/regex-automata/src/nfa/thompson/` at
`rust-lang/regex` commit `72d650cb0a880a01ab6dc2137c0888e8f89740f7`
(regex-automata 0.4.18). The top-level status and ordering remain in
[parity.md](parity.md); individual symbols remain in the inventory TSVs.

## 3c3a — UTF-8 tries and bounded maps (complete)

Scope: `literal_trie.rs`, `range_trie.rs`, and `map.rs`, including their
private traversal/insert helpers and debug formatting. The pinned `zap`,
`maker`, `no_splits`, and `splits` tests are represented directly in
`spec/nfa_literal_trie_vendor_spec.cr` and
`spec/nfa_range_trie_vendor_spec.cr`. The range split spec checks all source
cases, and direct compiled-NFA searches check literal priority. Additional
source-derived specs cover reverse literals, sorted range insertion,
free-list reuse, Debug output, and direct-mapped cache collisions/versioned
clear in `spec/nfa_utf8_map_vendor_spec.cr`.

Rust's `NextInsert` and `Split` fixed-size arrays map to Crystal
`StaticArray`; range-trie state and scratch buffers are reused, and literal
trie compilation uses value frames with moved sparse transition arrays.
`literal_trie.rs`'s `#[cfg(test)] compile_to_hir` helpers are intentionally
skipped as test-only diagnostics: their branch-order contract is tested through
the compiled NFA, with no runtime divergence or search-path cost. Compiler
ownership/reuse of these structures across Unicode classes is not part of
this file-level gate; it is explicitly in 3c3b.

An integration review also found that Crystal's empty-pattern compiler path
discarded UTF-8/reverse/look-matcher configuration. The pinned
`compiler.rs::Compiler::compile` ordering is asserted first in
`spec/nfa_compiler_vendor_contract_spec.cr` and corrected in
`src/regex/automata/hir_compiler.cr`.

Gate passed: all three source/test/file ledgers reconciled; `make install`,
`make format`, `make lint`, `make test`, `make parity`, `git diff --check`,
Crystal format check, and no-codegen build green (16,094 Crystal specs).
Benchmarks are not used
as evidence on this loaded host.

## 3c3b — HIR compiler algorithms (complete)

All 74 `compiler.rs` method rows and the file-level review are reconciled
against the pinned source. The 19 unchanged native Rust compiler tests pass
offline; the 38 original assertion locations map to exact Crystal graph
checks in `spec/thompson_syntax_adoption_spec.cr` and the assertion audit.
New source-derived red-green specs in `spec/nfa_compiler_vendor_contract_spec.cr`
cover retained builder/Unicode scratch identities, immutable earlier NFAs,
empty-list configuration in the Crystal adapter, Rust's direct literal/look
state allocation, terminal `Match`, and all six dot variants in both directions.

`HirCompiler` clears and reuses its `Builder`; the builder retains one
`Utf8CompilerState`, `RangeTrie`, and 1,000-slot `Utf8SuffixMap`, each cleared
at the same class boundary as Rust's `Compiler`. Forward Unicode uses the
ordered UTF-8 compiler, reverse unshrunk compilation uses suffix caching,
and reverse shrunk compilation traverses the range trie in lexical order.
Literal and look lowering now emit Rust's directly patchable states. Crystal's
raw `DotNode` compatibility path is normalized through `Hir.dot`, as Rust's
HIR smart constructor does, rather than building a separate, oversized byte
graph. The Crystal-only `Match.next` edge is removed from both construction
and final NFA states; direct Builder convenience helpers convert an endpoint
`Match` to `Empty` only when composing graphs. The extra conversion is
construction-only, preserves final graph semantics, and adds no search-time
branch or allocation. It exists solely for the Crystal convenience helpers,
which Rust's low-level Builder does not expose.

The pinned source/test/file inventories and top-level roadmap carry the
completion state. Benchmarks were skipped because this host is loaded; no
throughput claim is made.
