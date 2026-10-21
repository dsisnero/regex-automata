# regex-automata

Crystal regular-expression automata and shared search APIs. The library is
under active development; see [Development](docs/development.md) for its
current compatibility status and source of truth.

## Installation

Add to `shard.yml`:

```yaml
dependencies:
  regex-automata:
    github: dsisnero/regex-automata
```

Then run:

```bash
shards install
```

## Usage

```crystal
require "regex-automata"

regex = Regex::Automata::Meta::Regex.new("[a-z]+")
match = regex.find("abc123")
puts({match.not_nil!.start, match.not_nil!.end}) # => {0, 3}
```

## Status

Meta, Thompson NFA, dense/sparse/one-pass DFA, and lazy hybrid interfaces are
available. Compatibility is still being verified; consult
[Development](docs/development.md) before relying on a specific engine or wire
format.

## Development and verification

From this directory:

```bash
make install    # Install dependencies
make format     # Format code
make lint       # Run ameba linter
make test       # Run specs
make parity     # Check Rust source and test inventories
```

## Documentation

- [Resuming work](docs/resuming.md)
- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Coding guidelines](docs/coding-guidelines.md)
- [Testing](docs/testing.md)
- [PR workflow](docs/pr-workflow.md)

## License

MIT
