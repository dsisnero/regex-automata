#!/usr/bin/env bash
# Independent pinned-Rust oracle; all generated data stays under temp/.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p temp/final-cross-engine
export CARGO_TARGET_DIR="$PWD/temp/rust-target"
export CARGO_NET_OFFLINE="${CARGO_NET_OFFLINE:-true}"
export CRYSTAL_CACHE_DIR="$PWD/temp/crystal-cache"
cat > temp/final-cross-engine/Cargo.toml <<'MANIFEST'
[package]
name = "final-cross-engine"
version = "0.0.0"
edition = "2021"
[[bin]]
name = "final-cross-engine"
path = "../../spec/support/final_cross_engine_oracle.rs"
[dependencies]
regex-automata = { path = "../../vendor/regex/regex-automata" }
# Use the versions recorded for the pinned native oracle.
memchr = "=2.8.1"
aho-corasick = "=1.1.4"
[[bin]]
name = "final-shared-oracle"
path = "../../spec/support/final_shared_oracle.rs"
MANIFEST
python3 spec/support/final_cross_engine_cases.py > temp/final-cross-engine/cases.tsv
cargo run --manifest-path temp/final-cross-engine/Cargo.toml --bin final-shared-oracle
cargo run --manifest-path temp/final-cross-engine/Cargo.toml --bin final-cross-engine < temp/final-cross-engine/cases.tsv > temp/final-cross-engine/rust.tsv
crystal build ${FINAL_CRYSTAL_FLAGS:-} spec/support/final_cross_engine_check.cr -o temp/final-cross-engine/check
temp/final-cross-engine/check < temp/final-cross-engine/cases.tsv > temp/final-cross-engine/crystal.tsv
diff -u temp/final-cross-engine/rust.tsv temp/final-cross-engine/crystal.tsv
printf 'All %s engine results match pinned Rust\n' "$(wc -l < temp/final-cross-engine/rust.tsv)"
