#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
work="$root/temp/final-perf"
export CRYSTAL_CACHE_DIR="$root/temp/crystal-cache"
export CARGO_TARGET_DIR="$root/temp/rust-target"
export CARGO_NET_OFFLINE="${CARGO_NET_OFFLINE:-true}"
mkdir -p "$work"
case "${1:-check}" in
  prepare)
    mkdir -p "$work/baseline/bench"
    git archive 8edddc8 | tar -x -C "$work/baseline"
    ln -sfn "$root/lib" "$work/baseline/lib"
    cp bench/final_signoff.cr "$work/baseline/bench/final_signoff.cr"
    cat > "$work/Cargo.toml" <<'MANIFEST'
[package]
name = "final-signoff-bench"
version = "0.0.0"
edition = "2021"
[[bin]]
name = "final-signoff-bench"
path = "../../bench/final_signoff.rs"
[dependencies]
regex-automata = { path = "../../vendor/regex/regex-automata" }
memchr = "=2.8.1"
aho-corasick = "=1.1.4"
MANIFEST
    cargo build --release --manifest-path "$work/Cargo.toml"
    crystal build --release "$work/baseline/bench/final_signoff.cr" -o "$work/baseline-bench"
    crystal build --release bench/final_signoff.cr -o "$work/current-bench"
    crystal build --release -Ddfa_unrolled_search bench/final_signoff.cr -o "$work/unrolled-bench"
    ;;
  check)
    "$work/baseline-bench" --check > "$work/baseline-check.tsv"
    "$work/current-bench" --check > "$work/current-check.tsv"
    "$work/unrolled-bench" --check > "$work/unrolled-check.tsv"
    "$CARGO_TARGET_DIR/release/final-signoff-bench" --check > "$work/rust-check.tsv"
    diff -u "$work/rust-check.tsv" "$work/baseline-check.tsv"
    diff -u "$work/rust-check.tsv" "$work/current-check.tsv"
    diff -u "$work/rust-check.tsv" "$work/unrolled-check.tsv"
    ;;
  run)
    # Do not time on the operator's loaded host. CI must pass the idle gate
    # before each separate process, after all builds and correctness gates.
    for run in 1 2 3; do
      for implementation in baseline current unrolled rust; do
        python3 scripts/final_perf_idle.py
        if [[ "$implementation" == rust ]]; then
          binary="$CARGO_TARGET_DIR/release/final-signoff-bench"
        else
          binary="$work/$implementation-bench"
        fi
        "$binary" > "$work/$implementation-$run.tsv"
      done
    done
    python3 scripts/summarize_final_perf.py "$work" > "$work/summary.md"
    cat "$work/summary.md"
    ;;
  *) echo 'usage: benchmark_final_signoff.sh prepare|check|run' >&2; exit 2 ;;
esac
