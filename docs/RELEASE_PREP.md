# Release Preparation — v1.15.0

## Summary

Additive `SnapDiff::Config`, two failure-masking fixes in the `pending_if_new`
teardown paths, a `BacktraceFilter` boundary fix, and an internal hygiene pass.

## Release Checklist

### Pre-Release

- [x] Update version to `1.15.0`
- [x] Run tests: `bundle exec rake test:unit` (267 runs, 0 failures)
- [x] Update CHANGELOG.md

### Release (One Click)

1. Push to GitHub
2. Go to [Actions → Release](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/release.yml)
3. Click **Run workflow**, enter `1.15.0`
4. Workflow will: test → tag → publish to RubyGems → create GitHub Release

### Post-Release

- [ ] Verify on [RubyGems](https://rubygems.org/gems/capybara-screenshot-diff)
- [ ] Verify GitHub Release created

## What Changed

### Added
- `SnapDiff::Config` — flat, additive consolidation of all 27 settings
  (`SnapDiff.config` / `SnapDiff.configure`); old accessors stay canonical

### Fixed
- `pending_if_new` no longer converts real teardown/after-hook failures into
  pending tests (Minitest defers to `after_teardown`; RSpec uses `append_after`;
  known residual for consumer `append_after` hooks documented)
- `BacktraceFilter` custom `lib_directory` matches on a path boundary

### Internal
- Guard tests for failure masking and skip-area/VCS-baseline regressions;
  two files merged into sole consumers (constant paths preserved)

See [CHANGELOG.md](../CHANGELOG.md) for full details.
