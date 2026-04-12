# Development

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/dsisnero/regex-automata
   cd regex-automata
   ```

2. Install dependencies:
   ```bash
   make install
   ```

3. Run tests:
   ```bash
   make test
   ```

## Development Workflow

### Porting New Features

1. **Identify upstream source**: Locate corresponding Rust code in `vendor/regex/regex-automata/`
2. **Create inventory entry**: Use `cross-language-crystal-parity` skill to track
3. **Port behavior**: Translate Rust to Crystal preserving semantics
4. **Add tests**: Port upstream tests as Crystal specs
5. **Verify parity**: Run quality gates and compare with upstream

### Code Organization

- `src/`: Crystal implementation
- `spec/`: Crystal specs (ported from Rust tests)
- `vendor/regex/regex-automata/`: Upstream Rust source
- `docs/`: Documentation

### Quality Gates

Always run before committing:
```bash
make format  # Crystal formatter
make lint    # Ameba linter
make test    # Spec tests
```

## Building

The library is built automatically when running tests. For production builds:

```bash
crystal build src/regex-automata.cr
```

## Debugging

### Common Issues

1. **Numeric type mismatches**: Use explicit types (`_u8`, `_i32`) for Rust parity
2. **Binary data**: Use `Bytes` (`Slice(UInt8)`) not `String` for raw bytes
3. **Error handling**: Preserve Rust error semantics exactly

### Profiling

Use Crystal's built-in profiling:
```bash
crystal spec --profile
```