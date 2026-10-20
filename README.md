# regex-automata

This repository is a Crystal port of https://github.com/rust-lang/regex (specifically the `regex-automata` crate).

It ports Rust's `regex-automata` engines and shared search APIs to Crystal.
The pinned Rust source and tests, not the examples below, define the parity
contract; remaining differences are tracked in [plans/parity.md](plans/parity.md).

**Upstream source:** `vendor/regex/regex-automata/` (git submodule)
**Upstream revision:** Pinned to commit `72d650cb0a880a01ab6dc2137c0888e8f89740f7` (regex-automata 0.4.18, regex-syntax 0.8.11)

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

The port has Meta, Thompson NFA, dense/sparse/one-pass DFA, and lazy hybrid
interfaces. Their full vendor test matrices, sparse/DFA wire compatibility,
and other remaining parity work are **not** signed off; see the roadmap for
the exact gates. In particular, Crystal's owned DFA deserialization is not
Rust's zero-copy borrowed format.

## Development and verification

From this directory:

```bash
make install    # Install dependencies
make format     # Format code
make lint       # Run ameba linter
make test       # Run specs
make parity     # Check Rust source and test inventories
```

## Upstream Reference

- Rust source of truth: `vendor/regex/regex-automata/`
- Consumer integration should be verified against the engine-specific Crystal specs.

## License

MIT
