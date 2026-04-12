# Release Preparation — v1.12.0

## Summary

71 commits since v1.11.0 with new features, performance improvements, and default behavior changes.

## Release Checklist

### Pre-Release

- [x] Update version to `1.12.0`
- [x] Run tests: `bundle exec rake test` (210 runs, 0 failures)
- [x] Add CHANGELOG.md
- [x] Add docs/UPGRADING.md

### Release (One Click)

1. Push to GitHub
2. Go to [Actions → Release](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/release.yml)
3. Click **Run workflow**, enter `1.12.0`
4. Workflow will: test → tag → publish to RubyGems → create GitHub Release

### Post-Release

- [ ] Verify on [RubyGems](https://rubygems.org/gems/capybara-screenshot-diff)
- [ ] Verify GitHub Release created

## What Changed

### New Features
- HTML reporter with interactive dashboard
- `Diff.compare` for standalone image comparison
- Perceptual color distance (dE00) for anti-aliasing
- `assert_no_screenshot_changes` DSL method
- `Diff.configure` block helper
- Ruby 3.5 & 4.0 support

### Behavior Changes
- `blur_active_element` defaults to `true`
- `hide_caret` defaults to `true`
- `fail_if_new` defaults to `true` in CI
- SVN support removed
- ActiveSupport no longer required

### Performance
- Faster ChunkyPNG shift-detection (eliminated allocations)
- Cached computations in VIPS driver
- Memoized region area size

See [CHANGELOG.md](../CHANGELOG.md) for full details.
