# Development

This is a Crystal port of Rust's `regex-automata` crate from
[`rust-lang/regex`](https://github.com/rust-lang/regex). The source of truth is
the checked-in `vendor/regex/regex-automata/` submodule, pinned to
`72d650cb0a880a01ab6dc2137c0888e8f89740f7` (regex-automata 0.4.18;
regex-syntax 0.8.11). Do not silently substitute a newer upstream release.

The current compatibility status and feature sequence are in
[plans/parity.md](../plans/parity.md). Its **Where we are** block is the resume
point; [docs/resuming.md](resuming.md) gives the session checklist. Source and
test dispositions live in `plans/inventory/`. The checked-in Rust tests are
the behavioral contract, while passing Crystal-only tests are not proof of
parity. Full engine-specific vendor matrices and wire compatibility remain
separate signoff work.

## Layout

- `src/regex/automata/`: Crystal implementation
- `spec/`: Crystal specs and shared vendor-suite reader
- `vendor/regex/regex-automata/`: pinned Rust source and tests
- `plans/`: roadmap, history, and parity inventories
- `temp/`: ignored local scratch, caches, and Rust test targets

## Feature workflow

1. Read the relevant Rust module and nearest tests, then check the plan and
   inventory for the feature's exact scope.
2. Port tests first and observe a failure; implement in small red-green cycles
   without changing upstream expectations.
3. Run focused Crystal/Rust checks, then the full gates in
   [AGENTS.md](../AGENTS.md). Update inventory evidence and the plan's
   **Where we are** block.
4. Close and commit one complete feature, not a helper-sized milestone. Use
   `port: <feature>` with a body recording tests, divergences, gates, and pin.

Use `make install` for dependencies, `make parity` for inventory drift, and
`make clean` to remove this repo's `./temp` directory. On this heavily loaded
host, one-off timings are not reliable performance evidence.
