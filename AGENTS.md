# Agent Engineering Guide

## Source of Truth

This repository is a Crystal port of Rust's `regex-automata` crate from the `rust-lang/regex` repository.

**Upstream source:** `vendor/regex/regex-automata/` (git submodule)
**Upstream revision:** Pinned to commit `839d16bc65b60e2006d3599d20bfa6efc14049d8` (regex-syntax-0.8.10)

## Quality Gates

Run these commands to ensure code quality:

```bash
make install    # Install dependencies
make format     # Format code
make lint       # Run ameba linter
make test       # Run specs
```

## Porting Workflow

1. **Rust-first source of truth**: Read the relevant Rust code and Rust tests before editing Crystal for a feature
2. **Inventory-first**: Use `cross-language-crystal-parity` skill to track parity inventory
3. **Behavior-faithful**: Preserve upstream semantics exactly
4. **Feature-level TDD**: Work each top-level feature through many small red-green-fix cycles driven by upstream behavior
5. **Focused then broad verification**: Run focused checks during each TDD step, then full parity/gate checks before closing the feature
6. **No helper-sized stopping points**: Do not stop or report progress while a top-level feature is still materially incomplete
7. **Commit inside the feature loop**: Small green commits are allowed, but the feature checkbox stays open until the whole feature is done

## Crystal Conventions

- Use explicit numeric types (`_u8`, `_i32`, etc.) where behavior depends on signedness/range
- Use `Bytes` (`Slice(UInt8)`) for binary semantics
- Preserve parameter order, edge cases, and error behavior exactly
- Port Rust tests to Crystal specs with identical assertions

## Dependencies

- `regex-syntax`: Crystal port of Rust's regex-syntax crate
- `ameba`: Development dependency for linting

## Related Skills

- `porting-to-crystal`: Default implementation workflow
- `cross-language-crystal-parity`: Inventory and drift tracking
- `crystal-shard-lib-patch`: For modifications to vendored shard code