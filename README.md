# regex-automata

Crystal regular-expression automata and shared search APIs, ported from
Rust's regex-automata.

## Installation

Add to `shard.yml`:

```yaml
dependencies:
  regex-automata:
    github: dsisnero/regex-automata
    version: "~> 0.2.0"
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

Version 0.2.0 completes the verification plan for the pinned Rust
regex-automata 0.4.18 checkout. The port includes Meta, Thompson NFA,
dense, sparse and one-pass DFAs, and lazy hybrid search. See the release
notes for wire compatibility and build-limit changes. [Changelog](CHANGELOG.md)

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
- [Changelog](CHANGELOG.md)

## License

MIT
