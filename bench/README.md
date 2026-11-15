The final signoff harness compares phase-7 `8edddc8`, the current Crystal
checkout and pinned Rust on identical public API workloads. Run
`scripts/benchmark_final_signoff.sh prepare` then `check` for deterministic
result verification. Generated data and binaries stay under `temp/final-perf`.

`run` requires an idle Linux runner, verifies at least 90% idle CPU before
each process, and executes three independent process repeats. `BENCH_MS`,
`BENCH_SAMPLES` (at least four, first discarded) and `BENCH_SIZE` parameterize
the work. Build and fixture setup are excluded from search measurements;
`dense-build` intentionally measures construction from a precompiled NFA.
Every result is consumed and checked. Crystal allocation probes run separately
from timing and report GC-tracked bytes, excluding native malloc allocations;
they compare Crystal revisions, not Rust allocator layouts.

The matrix covers byte1/2/3, short/long/periodic substring hits and misses,
Teddy 2/16/65, pooled and explicit-cache Meta, nonaccelerated dense search and
dense construction. It establishes performance only for these workloads on
the recorded runner. Preserve raw samples and regressions alongside summaries.

`--alloc` on a Crystal benchmark binary performs only the separate fixed-count
allocation probes, with no clock samples. This can be used on a busy host to
check allocation changes; it supplies no throughput or latency evidence.
`scalar` is a comparison build with `-Ddfa_scalar_search`. The default build
uses the four-step forward loop. Both builds use the scalar reverse loop.
