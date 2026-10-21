# Pull Request Workflow

## Overview

This document outlines the workflow for pull requests (PRs), including code
quality, pinned Rust parity evidence, and maintainable contributions.

## PR Creation

### Before Creating a PR

1. **Ensure quality gates pass**: use the current commands in
   [AGENTS.md](../AGENTS.md) and record their results in the PR.

2. **Verify upstream parity**:
   - Use `cross-language-crystal-parity` skill for inventory tracking
   - Ensure all ported behavior matches Rust exactly
   - Include upstream test ports for new functionality

3. **Update documentation**:
   - Update `README.md` if API changes
   - Add/update doc comments for public API
   - Update `CHANGELOG.md` (if applicable)

### PR Template

```markdown
## Summary
Brief description of changes (1-3 bullet points)

## Upstream Reference
- Rust source file: `vendor/regex/regex-automata/path/to/file.rs`
- Upstream commit: `72d650cb0a880a01ab6dc2137c0888e8f89740f7`
- Related upstream issue/PR: #123 (if applicable)

## Changes
- [ ] Behavior parity with Rust upstream
- [ ] All upstream tests ported
- [ ] Quality gates pass (`make format`, `make lint`, `make test`, `make parity`)
- [ ] Documentation updated
- [ ] CHANGELOG updated (if user-facing change)

## Testing
- [ ] All existing tests pass
- [ ] New tests added for new functionality
- [ ] Integration tests pass with dependent crates

## Notes
Any additional context, design decisions, or trade-offs.
```

## PR Review Process

### Reviewer Checklist

1. **Behavior Parity**:
   - Does the code match Rust upstream semantics exactly?
   - Are edge cases handled identically?
   - Are error conditions preserved?

2. **Code Quality**:
   - Follows Crystal conventions and coding guidelines
   - Proper type annotations
   - Clear naming and documentation

3. **Testing**:
   - All relevant upstream tests ported
   - New tests for new functionality
   - Test coverage maintained

4. **Documentation**:
   - Public API documented
   - README updated if needed
   - CHANGELOG updated for user-facing changes

### Common Review Comments

- "Please add explicit type annotations for public methods"
- "This should use `Bytes` instead of `String` for binary data"
- "Please port the corresponding Rust test from upstream"
- "Add a `# :nodoc:` comment for internal implementation details"

## PR Approval Criteria

A PR can be merged when:

1. Required review and available checks pass.
2. Behavior parity is verified against the pinned upstream tests, with any
   remaining divergence documented.
3. Documentation and inventory evidence are updated.
4. Breaking changes are discussed before merge.

## Post-Merge

After PR merge:

1. **Confirm inventory**: Verify the feature's inventory and roadmap changes
   were included before merge; do not defer them until afterward.
2. **Verify release readiness**: If applicable, prepare for release
3. **Close related issues**: Reference PR in any related GitHub issues

## Hotfix/Backport Process

For critical bug fixes:

1. Create branch from affected release tag
2. Apply minimal fix to address issue
3. Port corresponding Rust fix if available
4. Create PR targeting release branch
5. After merge, cherry-pick to main if applicable

## Release PRs

For version releases:

1. Update `shard.yml` version
2. Update `CHANGELOG.md` with release notes
3. Create PR with title "Release vX.Y.Z"
4. After merge, tag release in GitHub
