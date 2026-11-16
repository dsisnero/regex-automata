# Development

This is a Crystal port of Rust's `regex-automata` crate from
[`rust-lang/regex`](https://github.com/rust-lang/regex). The source of truth is
the checked-in `vendor/regex/regex-automata/` submodule, pinned to
`72d650cb0a880a01ab6dc2137c0888e8f89740f7` (regex-automata 0.4.18;
regex-syntax 0.8.11). Do not silently substitute a newer upstream release.

The Crystal shard release is 0.2.1. The signoff covers engine-specific vendor
matrices, 16,848 cross-engine comparisons, and native dense and sparse wire
formats. It records the differences in storage, search dispatch and finite
DFA determinization limits. [Final vendor signoff](../plans/feature-final-signoff.md)

The **Where we are** block tracks the port. Source and test dispositions live
in `plans/inventory/`. Use the checked-in Rust tests as the behavioral
contract. [Parity roadmap](../plans/parity.md) · [Resuming work](resuming.md)

## Layout

- `src/regex/automata/`: Crystal implementation
- `spec/`: Crystal specs and shared vendor-suite reader
- `vendor/regex/regex-automata/`: pinned Rust source and tests
- `plans/`: roadmap, history, and parity inventories
- `temp/`: ignored local scratch, caches, and Rust test targets

## Feature workflow

1. Read the relevant Rust module and nearest tests, then check the plan and
   inventory for the feature's exact scope.
2. Port tests first and observe a failure; implement in small red-green cycles
   without changing upstream expectations.
3. Run focused Crystal/Rust checks, then the full gates in
   [AGENTS.md](../AGENTS.md). Update inventory evidence and the plan's
   **Where we are** block.
4. Close and commit one complete feature, not a helper-sized milestone. Use
   `port: <feature>` with a body recording tests, divergences, gates, and pin.

Use `make install` for dependencies, `make parity` for inventory drift, and
`make clean` to remove this repo's `./temp` directory. On this heavily loaded
host, one-off timings are not reliable performance evidence.

## Dense DFA wire compatibility

Dense DFA serialization uses the pinned Rust native v2 format. The reader
accepts the host's native endianness and checks alignment; the writers support
little, big, and native endian output. The `to_bytes_*` tuple contains bytes
and initial alignment padding, while `write_to_*` returns bytes written.
The former Crystal `CRDFA001` format is superseded.

The [DFA wire feature plan](../plans/feature-dfa-wire.md) records generated
Rust byte fixtures, malformed-input coverage, the offline cross-language
check (`scripts/check_dense_wire.sh`), and the pin's quit-byte decoding behavior.
Sparse DFAs now use Rust's packed byte-offset state representation and native
v2 wire format. Sparse `to_bytes_*` returns `Bytes` directly; it has no dense
alignment-padding tuple. Its memory query counts packed transition and start
payloads, as Rust does. The former `CRSFA001` dense wrapper is superseded.
DFA regex wrappers preserve the pinned forward/reverse search contract and
accept Input as well as String/Bytes. Wrapper builder configuration mutates
and returns the builder; clone makes an independent configuration snapshot.
Regex clone copies both owned automata. The feature plan records source
oracles, wrapper representation limits and construction/search costs.
