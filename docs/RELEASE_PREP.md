# Release Preparation — v1.14.0

## Summary

SnapDiff namespace aliases (ADR-004 PR 9), standalone-require fix, and three
internal consolidation refactors (ADR-004 PR 2/PR 7, teardown logic).

## Release Checklist

### Pre-Release

- [x] Update version to `1.14.0`
- [x] Run tests: `bundle exec rake test:unit` (green)
- [x] Update CHANGELOG.md

### Release (One Click)

1. Push to GitHub
2. Go to [Actions → Release](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/release.yml)
3. Click **Run workflow**, enter `1.14.0`
4. Workflow will: test → tag → publish to RubyGems → create GitHub Release

### Post-Release

- [ ] Verify on [RubyGems](https://rubygems.org/gems/capybara-screenshot-diff)
- [ ] Verify GitHub Release created

## What Changed

### Added
- `SnapDiff` namespace aliases — `SnapDiff::Comparison`, `SnapDiff.compare`,
  `SnapDiff.start` (additive; deprecations deferred to v2.0)

### Fixed
- Standalone `require "capybara_screenshot_diff"` + `Diff.compare` no longer
  raises `NameError` (missing drivers require)

### Internal
- `DifferenceFinder` merged into `ImageCompare`; `AnnotationService` extracted
  from `Reporters::Default` (public surface preserved); `pending_if_new`
  teardown consolidated across the three framework adapters; driver-coverage
  banner + CI guard in the test suite

See [CHANGELOG.md](../CHANGELOG.md) for full details.
