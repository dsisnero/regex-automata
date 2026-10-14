# Testing

## Test Structure

Tests are organized in `spec/` directory mirroring the `src/` structure:

```
spec/
├── nfa_spec.cr          # NFA tests
├── dfa/
│   ├── builder_spec.cr  # DFA builder tests
│   └── dense_spec.cr    # Dense DFA tests
└── hybrid/
    └── lazy_spec.cr     # Hybrid lazy DFA tests
```

## Running Tests

### Basic Test Run
```bash
make test
# or
crystal spec
```

### Specific Test File
```bash
crystal spec spec/nfa_spec.cr
```

### Specific Test Example
```bash
crystal spec spec/nfa_spec.cr:15  # Line 15
```

### With Coverage
```bash
crystal spec --coverage
```

### With Profiling
```bash
crystal spec --profile
```

## Test Philosophy

### Behavior-First Testing

Tests are ported directly from Rust upstream to ensure behavior parity. Each Rust `#[test]` function becomes a Crystal `it` block.

### Test Porting Workflow

1. **Locate upstream test**: Find corresponding test in `vendor/regex/regex-automata/tests/`
2. **Create spec file**: Mirror Rust test module structure
3. **Port assertions**: Convert Rust `assert!`, `assert_eq!` to Crystal `should`
4. **Verify behavior**: Run test and compare with Rust output

### Example: Porting Rust Test

```rust
// Rust test in vendor/regex/regex-automata/tests/nfa.rs
#[test]
fn test_empty_nfa() {
    let nfa = NFA::new("");
    assert!(nfa.is_match(""));
    assert!(!nfa.is_match("a"));
}
```

```crystal
# Crystal spec in spec/nfa_spec.cr
describe "NFA" do
  it "matches empty string" do
    nfa = NFA.new("")
    nfa.is_match("").should be_true
    nfa.is_match("a").should be_false
  end
end
```

## Test Data

Test data files are kept in `spec/fixtures/` when needed. For upstream test data:

1. Copy from `vendor/regex/regex-automata/testdata/`
2. Preserve file structure and encoding
3. Document any modifications needed for Crystal

## Integration Tests

Integration tests verify the library works with dependent crates:

- `regex-syntax`: HIR compilation
- Consumer code (e.g., Logos): End-to-end matching

## Property-Based Testing

Consider using property-based testing for complex invariants:

```crystal
it "always returns same result for same input" do
  property do |pattern : String, input : String|
    nfa1 = NFA.new(pattern)
    nfa2 = NFA.new(pattern)
    nfa1.is_match(input).should eq(nfa2.is_match(input))
  end
end
```

## Continuous Integration

Tests run automatically on:
- Every commit via GitHub Actions
- PR merges to main branch
- Release tagging

CI checks:
- All specs pass
- Code formatting (`crystal tool format --check`)
- Linting (`ameba`)
- Coverage thresholds

## Syntax dependency adoption and exact Thompson graphs

```bash
shards install
python3 scripts/check_thompson_syntax_adoption.py
```

The runtime dependency is pinned in `shard.yml` to reviewed regex-syntax commit
`077d107e69b62251fb95f29f897a6bf10fbb8067`. Use normal `lib/` resolution;
no `CRYSTAL_PATH`, path dependency, or override selects a different checkout.
The smoke test checks the actual installed parser's `a|b` normalization and
its reserved LookSet bits and full-byte range length fixes.

The oracle compiles the pinned Rust source directly, without registry access.
All 19 original Thompson compiler tests execute with their assertions unchanged.
Unrelated Rust test modules are disabled in a temporary source copy to avoid
Cargo dev dependencies. Rust's private test-only unanchored-prefix option is
exposed only in a second disposable oracle build. Production vendor files are
never edited. Default-prefix cases also verify the public production behavior.

The 188 exact graphs include all 31 original compiler graph inputs and 157
explicit native characterizations. They compare state types, IDs, order,
transition ranges and targets, ordered branches, capture slots, pattern starts,
anchored/unanchored starts, group counts, UTF-8/reverse flags, and empty-match
metadata. Characterizations cover syntax normalization, all 18 look assertions,
reverse/shrink modes, captures, Unicode scalar boundaries, and invalid bytes.
The companion ledger accounts for all 38 original compiler assertion locations.
This is an integration signoff for syntax adoption, not full NFA API, limits,
serialization, memory-accounting, or private-helper parity.

To regenerate after reviewing the pinned native behavior:

```bash
python3 scripts/check_thompson_syntax_adoption.py --write-fixture --rust-only
python3 scripts/check_thompson_syntax_adoption.py
```

Generated source copies, binaries and logs stay in
`temp/thompson-syntax-adoption/`. Crystal output never establishes expectations.

A fresh empty `SHARDS_CACHE_PATH` was used to install the pinned commit from
GitHub, and every installed `src/` object matched the remote Git tree. The
existing singleton-byte wrapper spec was corrected after a native assertion
confirmed `(?-u:[\xFF])` becomes `Literal([255])` with UTF-8 disabled.


## Direct-HIR singleton alternation compatibility

```bash
python3 scripts/check_direct_hir_alternation.py
```

This rebuilds the pinned native oracle and runs all 19 original Rust compiler
unit tests before comparing 138 additional native graph characterizations.
The fixture is generated only by Rust `Hir::alternation` followed by Thompson
compilation. Crystal compares both smart constructors and raw `Alternation`
nodes, yielding 276 exact assertions. The matrix covers empty/singleton inputs,
branch order, duplicates, two/four-byte scalars, the surrogate boundary, invalid
bytes and byte sequences, mixed scalar/byte alternatives, and literal tries.
Forward/reverse and shrink modes are included; explicit captures are tested only
forward because Rust rejects them in reverse mode. These are new native
characterizations, separate from the original compiler test ports.

The initial test run failed 12 raw duplicate-scalar graphs. The fallback now
passes its canonical class through the existing syntax `character_class` smart
constructor, so a singleton class lowers to a literal exactly as Rust does.
A disposable copy with the fallback removed fails 49 comparisons. Retain this
compatibility path for public raw Crystal nodes; normalized parser and smart
constructor output does not need it. This is a Crystal representation contract,
not a claim that Rust permits bypassing its HIR constructors.

Regenerate deliberately after reviewing the native contract:

```bash
python3 scripts/check_direct_hir_alternation.py --write-fixture --rust-only
python3 scripts/check_direct_hir_alternation.py
```

### Compiler benchmark evidence

```bash
crystal build --release scripts/bench_direct_hir_alternation.cr -o temp/bench-direct-hir-final
ITERATIONS=3000 RUNS=4 temp/bench-direct-hir-final
```

Use the same harness with `hir_compiler.cr` from baseline `4d1ed89` to build
`temp/bench-direct-hir-baseline`, then compare the saved binaries. The recorded
comparison used three interleaved process repetitions, alternating executable
order. Each case builds the same preconstructed HIR 3,000 times per sample,
with one cold sample and three warm samples per process. GC collection and
parsing are outside timing; accumulated state counts keep results observable.
Single-threaded release builds used Crystal 1.21.1/LLVM 23.1.3 on arm64 macOS.
Numbers below are microseconds per public `build_from_hir` call, averaged across
three cold and nine warm samples respectively (2026-10-13).

| HIR input | Baseline cold | Corrected cold | Baseline warm | Corrected warm |
|---|---:|---:|---:|---:|
| Parsed scalar class | 164.329 | 184.330 | 167.444 | 186.628 |
| Parsed literal trie | 8.469 | 8.956 | 8.577 | 8.918 |
| Raw ASCII singletons | 1.784 | 2.165 | 1.915 | 2.230 |
| Raw Unicode singletons | 176.976 | 187.128 | 169.212 | 184.845 |
| Raw duplicate scalar | 174.549 | 2.086 | 178.216 | 2.045 |

The duplicate path avoids Unicode class compilation after literal lowering.
The raw ASCII mean adds about 0.315 microseconds; the other cases have overlapping
warm ranges on this shared host (for example parsed scalar 146.675–187.924 vs
155.875–221.672). This is a correctness fix with a targeted duplicate-path win,
not evidence of a general compiler throughput improvement. Logs and binaries
remain under `temp/`; the benchmark accepts `ITERATIONS` and `RUNS` for reruns.
