# Coding Guidelines

## Core Principle: Behavior Parity

**Upstream Rust behavior is the source of truth.** All porting decisions must preserve exact semantics from the Rust implementation.

## Language Mapping

### Rust → Crystal Conventions

| Rust | Crystal | Notes |
|------|---------|-------|
| `u8`, `i32`, etc. | `UInt8`, `Int32` | Use explicit numeric types |
| `Vec<u8>` | `Bytes` (`Slice(UInt8)`) | For binary data |
| `String` | `String` | For UTF-8 text only |
| `Result<T, E>` | Exception or union | Preserve error semantics |
| `Option<T>` | `T?` or `Nil \| T` | |
| `#[test]` | `it` blocks in specs | |
| `panic!` | `raise` | |

### Type Annotations

Always use explicit type annotations for public API:
```crystal
def compile(hir : Regex::Syntax::Hir) : NFA
  # ...
end
```

### Error Handling

Preserve Rust error behavior exactly:
- Same error conditions
- Same error messages (where applicable)
- Same recovery semantics

## Code Style

### Formatting

Use Crystal's built-in formatter:
```bash
crystal tool format src spec
```

### Naming

- **Modules**: `PascalCase` (e.g., `Regex::Automata`)
- **Classes**: `PascalCase` (e.g., `NFA`, `DFA::Builder`)
- **Methods**: `snake_case` (e.g., `find_longest_match`)
- **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `MAX_STATES`)

### Comments

- Document public API with Crystal doc comments (`#`)
- Preserve Rust doc comments when porting
- Add `# :nodoc:` for internal implementation details

## Testing Guidelines

### Porting Rust Tests

1. Convert Rust `#[test]` functions to Crystal `it` blocks
2. Preserve all assertions exactly
3. Keep test data/fixtures identical
4. Maintain test organization structure

### Example Port

```rust
// Rust
#[test]
fn test_nfa_construction() {
    let nfa = NFA::new("a|b");
    assert_eq!(nfa.states(), 5);
}
```

```crystal
# Crystal
it "constructs NFA" do
  nfa = NFA.new("a|b")
  nfa.states.should eq(5)
end
```

## Performance Considerations

- Use `Bytes` for binary operations (not `String`)
- Prefer `Slice` operations over copying
- Use explicit numeric types to avoid runtime checks
- Profile with `crystal spec --profile` for hotspots