# Pull Request Workflow

## Overview

This document outlines the workflow for contributing changes via pull requests (PRs). The process ensures code quality, behavior parity with upstream Rust, and maintainable contributions.

## PR Creation

### Before Creating a PR

1. **Ensure quality gates pass**:
   ```bash
   make format
   make lint
   make test
   ```

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
- Upstream commit: `839d16bc65b60e2006d3599d20bfa6efc14049d8`
- Related upstream issue/PR: #123 (if applicable)

## Changes
- [ ] Behavior parity with Rust upstream
- [ ] All upstream tests ported
- [ ] Quality gates pass (`make format`, `make lint`, `make test`)
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

1. ✅ At least one maintainer approves
2. ✅ All CI checks pass
3. ✅ Behavior parity verified with upstream
4. ✅ Documentation updated
5. ✅ No breaking changes without discussion

## Post-Merge

After PR merge:

1. **Update inventory**: Run `cross-language-crystal-parity` to update parity tracking
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