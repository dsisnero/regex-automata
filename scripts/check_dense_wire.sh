#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p temp/dense-wire-oracle
export TMPDIR="$PWD/temp"
export CRYSTAL_CACHE_DIR="$PWD/temp/crystal-cache"
export CARGO_TARGET_DIR="$PWD/temp/rust-target"
cat > temp/dense-wire-oracle/Cargo.toml <<'MANIFEST'
[package]
name = "dense-wire-oracle"
version = "0.0.0"
edition = "2021"
[[bin]]
name = "dense-wire-oracle"
path = "../../spec/support/dense_wire_oracle.rs"
[dependencies]
regex-automata = { path = "../../vendor/regex/regex-automata" }
MANIFEST
crystal run spec/support/generate_dense_wire.cr
cargo run --offline --manifest-path temp/dense-wire-oracle/Cargo.toml --bin dense-wire-oracle
