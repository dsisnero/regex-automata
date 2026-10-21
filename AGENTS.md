# regex-automata

> **How to resume:** read [plans/parity.md](plans/parity.md), especially its
> **Where we are** block, then confirm `git status` and run `make lint`,
> `make test`, and `make parity`. The operator checklist is in
> [docs/resuming.md](docs/resuming.md); do not reconstruct progress from chat.

Crystal port of Rust's `regex-automata` crate from
[`rust-lang/regex`](https://github.com/rust-lang/regex), vendored at
`vendor/regex/regex-automata/` (regex-automata 0.4.18, commit
`72d650cb0a880a01ab6dc2137c0888e8f89740f7`).

## Commands

```bash
make install  # Install Crystal dependencies
make update   # Update Crystal dependencies (intentional changes only)
make format   # Format src/ and spec/
make lint     # Run Ameba on src/ and spec/
make test     # Run Crystal specs
make parity   # Check Rust source and test inventories
make clean    # Remove this repo's ./temp directory
```

## Docs

- [Resuming work](docs/resuming.md)
- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Coding guidelines](docs/coding-guidelines.md)
- [Testing](docs/testing.md)
- [PR workflow](docs/pr-workflow.md)

## Principles

1. The pinned Rust source and nearest Rust tests are the source of truth.
2. Port upstream tests first, then implement through red-green TDD; never
   weaken an upstream assertion to make the port pass.
3. Preserve semantics, parameter order, edge cases, and errors. Follow Rust's
   optimization logic; use Crystal idioms only when behavior and hot-path cost
   are justified.
4. Use explicit numeric types when signedness/range matters and `Bytes`
   (`Slice(UInt8)`) for binary data.
5. Keep generated scratch data under `./temp`. Do not treat noisy timings on
   this loaded host as performance evidence.

## Session continuity

1. Read the **Where we are** block in [plans/parity.md](plans/parity.md) to
   identify the current feature, ordered next work, scope, and last gates.
2. Skim `git log --oneline -10` and `git status --short`; preserve unrelated
   changes and confirm the vendor submodule pin.
3. Run `make lint`, `make test`, and `make parity` before implementation to
   establish a baseline. Use focused specs while iterating and full gates at
   feature completion.

See [docs/resuming.md](docs/resuming.md) for the short checklist. Keep
per-symbol detail in [plans/inventory/rust_port_inventory.tsv](plans/inventory/rust_port_inventory.tsv),
not in the roadmap. If the roadmap grows, link feature-sized subplans from it.

## Definition of done

A top-level feature is complete only when its Rust API/behavior is implemented,
its relevant upstream tests have been ported and pass, affected source/test
inventory rows have evidence-backed dispositions, and the roadmap's **Where we
are** block is current. Document every remaining divergence with the Rust and
Crystal paths, necessity, observable equivalence, and hot-path cost; a passing
Crystal-only test is not Rust parity proof. Do not stop at helper-sized progress
while the feature is materially incomplete.

Run `make install`, `make format`, `make lint`, `make test`, `make parity`,
`git diff --check`, `crystal tool format --check src spec`, and
`crystal build --no-codegen src/regex-automata.cr` before closing a feature.
Commit each completed feature atomically before beginning the next.

## Commit convention

Use `port: <feature>` plus bullets for behavior, tests, inventory, divergences,
and gates. Include the upstream pin (`rust-lang/regex` regex-automata 0.4.18,
`72d650cb0a880a01ab6dc2137c0888e8f89740f7`) in the commit body.
