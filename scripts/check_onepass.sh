#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p temp/onepass-check
export CARGO_TARGET_DIR="$PWD/temp/rust-target"
cat > temp/onepass-check/Cargo.toml <<'MANIFEST'
[package]
name = "onepass-check"
version = "0.0.0"
edition = "2021"
[[bin]]
name = "onepass-check"
path = "../../spec/support/onepass_oracle.rs"
[dependencies]
regex-automata = { path = "../../vendor/regex/regex-automata" }
regex-test = { path = "../../vendor/regex/regex-test" }
MANIFEST
cargo run --offline --manifest-path temp/onepass-check/Cargo.toml > temp/onepass-check/actual.tsv
sed '/^#/d' spec/fixtures/onepass_suite.tsv > temp/onepass-check/expected.tsv
diff -u temp/onepass-check/expected.tsv temp/onepass-check/actual.tsv
