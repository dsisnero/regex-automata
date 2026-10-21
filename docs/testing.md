# Testing

Crystal specs are in [`spec/`](../spec/). The full local gate is `make test`;
focused examples can be run with `crystal spec spec/<file>_spec.cr` or a
file-and-line selector. The Makefile routes Crystal caches and temporary
artifacts to `./temp`.

## Parity test workflow

1. Read the relevant pinned Rust implementation and its nearest Rust test or
   `vendor/regex/testdata/` case.
2. Port the test to Crystal with the same inputs, assertions, and error
   expectations. Run it and confirm red before implementation.
3. Implement the smallest behavior change, then rerun the focused spec until
   green. Continue until the entire feature's upstream cases are covered.
4. Run `make install`, `make format`, `make lint`, `make test`, and
   `make parity`, plus the checks in [AGENTS.md](../AGENTS.md), before
   checking off the feature in [plans/parity.md](../plans/parity.md).

The shared fixture reader in `spec/support/vendor_regex_suite.cr` loads
vendor TOML cases. Engine-specific Rust blacklists and supported modes still
matter: a spot-check passing is not a full suite signoff. Exact coverage and
remaining cases are recorded in [plans/parity.md](../plans/parity.md) and
[plans/inventory/rust_test_parity.tsv](../plans/inventory/rust_test_parity.tsv).

Run pinned Rust tests from `vendor/regex` with Cargo's `--offline` option when
the local dependencies are cached. Put `CARGO_TARGET_DIR` under `./temp` and
request network access if a required dependency is unavailable; do not infer
Rust success from a Crystal-only run.

No repository GitHub Actions workflow is currently checked in, so local gate
results must be recorded explicitly in the feature commit or PR.
