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

## 3c3b — HIR compiler algorithms

Scope: `compiler.rs` public configuration/build contracts, HIR lowering,
greedy and reverse state order, capture/error precedence, Unicode class
strategies, literal/range trie and bounded-map integration, private UTF-8
compiler helpers, and the 19 pinned native compiler tests. The existing
assertion audit in `inventory/rust_thompson_compiler_assertion_audit.tsv`
is a starting point, not a file-level signoff.

Rust source paths to check individually: `Compiler::compile`,
`c_unicode_class`, `c_unicode_class_reverse_with_suffix`, `Utf8Compiler`,
and the `Config`/`WhichCaptures` contracts. Rust always streams forward
Unicode sequences into `Utf8Compiler`; reverse compilation uses suffix
caching when `shrink` is false and a lexicographically ordered `RangeTrie`
when `shrink` is true. Reuse compiler-owned trie and UTF-8 scratch storage
across class compilations. Audit the Crystal-only `Match.next` placeholder
against Rust's builder/compiler graph; remove it if possible, or record
necessity, observable equivalence, and construction cost.

Gate: every `compiler.rs` source/test/file row has pinned evidence; full
code gates green; update the top-level **Where we are** block and commit
3c3b atomically before phase 4.
