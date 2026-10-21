# Resuming work

Use this checklist at the start of a session; [plans/parity.md](../plans/parity.md)
is the progress source of truth, not chat history.

1. Read the plan's **Where we are** block for the current feature, ordered
   next work, scoping notes, last commit, and current gate evidence. Consult
   [rust_port_inventory.tsv](../plans/inventory/rust_port_inventory.tsv) for
   source-item status and [rust_test_parity.tsv](../plans/inventory/rust_test_parity.tsv)
   for upstream test status. Do not regenerate a curated ledger over manual
   work.
2. Check `git log --oneline -10`, `git status --short`, and
   `git submodule status vendor/regex`. Preserve any unrelated working-tree
   changes. The vendor pin is `72d650cb0a880a01ab6dc2137c0888e8f89740f7`.
3. Run `make lint`, `make test`, and `make parity` before changing code to
   establish the baseline. The Makefile keeps generated scratch files in
   `./temp`; `make clean` removes that directory when cleanup is wanted.
4. Take the first open feature from the plan. Read its pinned Rust source and
   nearest tests, port failing Crystal specs first, then implement in
   red-green cycles. Run focused checks as you go and the full gates in
   [AGENTS.md](../AGENTS.md) before closing the feature.
5. Update affected inventory rows and the plan's **Where we are** block. Mark
   only the completed feature checked, document unproven divergences, and
   commit it atomically with the `port: <feature>` convention from
   [AGENTS.md](../AGENTS.md).

If the plan is split, follow its links to the current feature document and
leave both the current and next phase visible in the top-level plan.
