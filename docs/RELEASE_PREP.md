# Release Preparation — v1.13.0

## Summary

Issue #191 API decoupling: `assert_matches_screenshot` becomes the primary
assertion method, plus a capture-only API and opt-in pending-instead-of-pass
for missing baselines.

## Release Checklist

### Pre-Release

- [x] Update version to `1.13.0`
- [x] Run tests: `bundle exec rake test:unit` (235 runs, 0 failures)
- [x] Update CHANGELOG.md

### Release (One Click)

1. Push to GitHub
2. Go to [Actions → Release](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/release.yml)
3. Click **Run workflow**, enter `1.13.0`
4. Workflow will: test → tag → publish to RubyGems → create GitHub Release

### Post-Release

- [ ] Verify on [RubyGems](https://rubygems.org/gems/capybara-screenshot-diff)
- [ ] Verify GitHub Release created

## What Changed

### New Features
- `capture_screenshot` DSL method — capture without comparing or asserting
- `compare:` option on `screenshot` — `compare: false` captures only
- `Capybara::Screenshot::Diff.pending_if_new` — mark tests skipped in teardown
  when a screenshot has no committed baseline (Minitest, RSpec, and Cucumber)

### Behavior Changes
- `assert_matches_screenshot` is now the primary assertion method; `screenshot`
  remains as a convenience wrapper and is safe to override in user test classes —
  the gem no longer calls it internally ([#191](https://github.com/snap-diff/snap_diff-capybara/issues/191))

See [CHANGELOG.md](../CHANGELOG.md) for full details.
