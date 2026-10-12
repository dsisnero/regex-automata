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
