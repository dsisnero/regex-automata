#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p temp/regex-wrapper-oracle
export CARGO_TARGET_DIR="$PWD/temp/rust-target"
cat > temp/regex-wrapper-oracle/Cargo.toml <<'MANIFEST'
[package]
name = "regex-wrapper-oracle"
version = "0.0.0"
edition = "2021"
[[bin]]
name = "regex-wrapper-oracle"
path = "../../spec/support/dfa_regex_oracle.rs"
[dependencies]
regex-automata = { path = "../../vendor/regex/regex-automata" }
MANIFEST
cargo run --offline --manifest-path temp/regex-wrapper-oracle/Cargo.toml
