#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p temp/sparse-wire-oracle
export TMPDIR="$PWD/temp"
export CRYSTAL_CACHE_DIR="$PWD/temp/crystal-cache"
export CARGO_TARGET_DIR="$PWD/temp/rust-target"
cat > temp/sparse-wire-oracle/Cargo.toml <<'MANIFEST'
[package]
name = "sparse-wire-oracle"
version = "0.0.0"
edition = "2021"
[[bin]]
name = "sparse-wire-oracle"
path = "../../spec/support/sparse_wire_oracle.rs"
[dependencies]
regex-automata = { path = "../../vendor/regex/regex-automata" }
MANIFEST
crystal run spec/support/generate_sparse_wire.cr
cargo run --offline --manifest-path temp/sparse-wire-oracle/Cargo.toml
