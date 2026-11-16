# Changelog

## Unreleased

- Fix dense DFA dead-state removal so pruning preserves delayed end-of-input
  matches, contextual and per-pattern starts, and quit behavior.

## v0.2.0

This release completes the Crystal port's signoff against Rust
`regex-automata` 0.4.18 at commit
`72d650cb0a880a01ab6dc2137c0888e8f89740f7`.

- Brings the Thompson NFA, PikeVM, bounded backtracker, dense and sparse DFA,
  one-pass DFA, hybrid DFA, and Meta search paths through the pinned vendor
  matrices. Updates capture extraction, bounded input, anchoring, UTF-8
  boundaries, and quit behavior to follow the pinned Rust contracts.
- Adopts Rust's native v2 dense and sparse DFA formats, with native-endian
  decoding and little-, big-, and native-endian writers. Rebuild existing
  serialized DFAs in the former Crystal formats `CRDFA001` and `CRSFA001`.
- Adds bounded byte search, Two-Way matching for long substring needles, and
  reusable dense determinizer scratch storage. Keeps the measured x86
  four-step forward search and scalar reverse search.
- Finite DFA determinization limits use Crystal's estimated auxiliary storage.
  Retune tight byte limits copied from Rust when they reject a build.

Validation passed 23,402 Crystal specs locally and on x86, the pinned Rust
suite, the native wire oracles, and 16,848 cross-engine comparisons.
[Vendor signoff](plans/feature-final-signoff.md)

## v0.1.2

Previous Crystal shard release. [Release tag](https://github.com/dsisnero/regex-automata/tree/v0.1.2)
