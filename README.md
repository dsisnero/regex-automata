# regex-automata

This repository is a Crystal port of https://github.com/rust-lang/regex (specifically the `regex-automata` crate).

This repository compiles `regex-syntax` HIR into Thompson NFA and DFA (plus a lazy Hybrid engine)
for fast token matching.

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
require "regex-syntax"
require "regex-automata"

hir = Regex::Syntax.parse("[a-z]+")
nfa = Regex::Automata::HirCompiler.new.compile(hir)
dfa = Regex::Automata::DFA::Builder.new(nfa).build

match = dfa.find_longest_match("abc123")
pp match # => {3, [PatternID(0)]}
```

### Lazy hybrid matching

```crystal
hybrid = Regex::Automata::Hybrid::LazyDFA.compile(Regex::Syntax.parse("foo|bar"))
pp hybrid.find_longest_match("bar!") # => {3, [PatternID(0)]}
```

## Current feature scope

- Thompson NFA builder for Logos-supported regex features
- DFA subset construction with look-around support used by Logos
- Anchored/unanchored start-state support
- EOI-aware transitions and longest-match search
- Lazy hybrid state expansion (`Hybrid::LazyDFA`)

## Development

From this directory:

```bash
crystal tool format src spec
crystal spec
```

For full-repo checks, run from repository root:

```bash
ameba src spec
crystal spec
```

## Upstream README Highlights

The upstream `regex-automata` crate exposes a variety of regex engines used by the `regex` crate. It provides a vast, sprawling and "expert" level API to each regex engine. The regex engines provided by this crate focus heavily on finite automata implementations and specifically guarantee worst case `O(m * n)` time complexity for all searches. (Where `m ~ len(regex)` and `n ~ len(haystack)`.)

### Key Features from Upstream

- **Multiple regex engines**: Exposes various regex engines with expert-level APIs
- **Finite automata focus**: Heavy emphasis on finite automata implementations
- **Worst-case guarantees**: `O(m * n)` time complexity for all searches
- **Zero-copy deserialization**: Support for zero-copy deserialization of DFAs in no-std environments
- **Extensive unsafe usage**: Carefully audited `unsafe` code for performance

### Safety Considerations

The upstream crate uses `unsafe` code in several places:
- `util::pool::Pool` for fast-path access that can avoid mutex locks. This
  Crystal port intentionally uses a bounded mutex-protected stack instead;
  normal Meta searches use explicit caches, while directly shared pools may
  contend under parallel use.
- `util::lazy::Lazy` for no-std variant of lazy initialization
- `dfa` module for zero-copy deserialization of DFAs
- Core search loops in `dfa` and `hybrid` modules for bounds check elision

## Development

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
