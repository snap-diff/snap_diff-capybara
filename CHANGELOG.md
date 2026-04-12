# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.12.0] - 2026-04-12

### Added
- HTML reporter for visual diff dashboard with premium UI, side-by-side comparison, and search ([#861183f](https://github.com/snap-diff/snap_diff-capybara/commit/861183f), [#993bcb9](https://github.com/snap-diff/snap_diff-capybara/commit/993bcb9))
- `Diff.compare` for standalone image comparison without Capybara or browser ([#1364048](https://github.com/snap-diff/snap_diff-capybara/commit/1364048))
- Perceptual color distance (dE00) support to VipsDriver for anti-aliasing tolerance ([#ce01d98](https://github.com/snap-diff/snap_diff-capybara/commit/ce01d98))
- `assert_no_screenshot_changes` to DSL for asserting no visual regressions ([#6d7e1a6](https://github.com/snap-diff/snap_diff-capybara/commit/6d7e1a6))
- `Diff.configure` block helper for simplified one-place configuration ([#5ffec5d](https://github.com/snap-diff/snap_diff-capybara/commit/5ffec5d))
- Ruby 3.5 support in CI ([#359b4e4](https://github.com/snap-diff/snap_diff-capybara/commit/359b4e4))
- Lightpanda browser as experimental CDP alternative to Chrome ([#ed59add](https://github.com/snap-diff/snap_diff-capybara/commit/ed59add))

### Changed
- `blur_active_element` now defaults to `true` to prevent cursor blinking artifacts ([#d60c30f](https://github.com/snap-diff/snap_diff-capybara/commit/d60c30f))
- `hide_caret` now defaults to `true` for stable screenshots ([#d60c30f](https://github.com/snap-diff/snap_diff-capybara/commit/d60c30f))
- `fail_if_new` now defaults to `true` in CI environments (when `ENV['CI']` is set) ([#715fa1b](https://github.com/snap-diff/snap_diff-capybara/commit/715fa1b))
- HTML report redesigned with premium UI and visual testing capabilities ([#993bcb9](https://github.com/snap-diff/snap_diff-capybara/commit/993bcb9))

### Deprecated
- SVN support removed — use Git for version control ([#2fe2792](https://github.com/snap-diff/snap_diff-capybara/commit/2fe2792))

### Removed
- SVN support completely removed ([#2fe2792](https://github.com/snap-diff/snap_diff-capybara/commit/2fe2792))
- `CaptureStrategy` layer inlined into `ScreenshotCoordinator` (internal refactoring) ([#7c3dcf7](https://github.com/snap-diff/snap_diff-capybara/commit/7c3dcf7))
- `ComparisonLoader` inlined into `ImageCompare` (internal refactoring) ([#2906681](https://github.com/snap-diff/snap_diff-capybara/commit/2906681))
- `ImagePreprocessor#call` method removed (was dead code) ([#c2023c5](https://github.com/snap-diff/snap_diff-capybara/commit/c2023c5))

### Fixed
- Remove ActiveSupport runtime dependency (`.presence` → plain Ruby) for lighter installations ([#e3b1a2e](https://github.com/snap-diff/snap_diff-capybara/commit/e3b1a2e))
- Remove ActiveSupport dependency from `fail_if_new` default ([#a960612](https://github.com/snap-diff/snap_diff-capybara/commit/a960612))
- Add `failure_message` and description to RSpec matcher for better error output ([#9550153](https://github.com/snap-diff/snap_diff-capybara/commit/9550153))
- Add recording instructions to missing baseline error ([#1b73136](https://github.com/snap-diff/snap_diff-capybara/commit/1b73136))
- Handle extensionless files in reporter filename generation ([#50191f6](https://github.com/snap-diff/snap_diff-capybara/commit/50191f6))
- Prevent nil crash in tempfile cleanup ([#444ac30](https://github.com/snap-diff/snap_diff-capybara/commit/444ac30))
- Reset `fail_if_new` in test setup for CI compatibility ([#5e4f8b1](https://github.com/snap-diff/snap_diff-capybara/commit/5e4f8b1))
- Remove misleading `filter_image_with_median` from ChunkyPNGDriver ([#567df71](https://github.com/snap-diff/snap_diff-capybara/commit/567df71))
- Freeze options hash and widen rescue in `files_identical?` ([#3331012](https://github.com/snap-diff/snap_diff-capybara/commit/3331012))
- Use `FileUtils.compare_file` for byte content comparison ([#16a776e](https://github.com/snap-diff/snap_diff-capybara/commit/16a776e))
- Resolve setup ordering issue with DSLStub in Ruby 4.0 ([#be53abb](https://github.com/snap-diff/snap_diff-capybara/commit/be53abb))
- Resolve Ruby 4.0 compatibility issues in CI ([#18d5564](https://github.com/snap-diff/snap_diff-capybara/commit/18d5564))
- Prevent skipping big changes in tolerance calculation ([#1d57a61](https://github.com/snap-diff/snap_diff-capybara/commit/1d57a61))
- Docker build — restore `.git` and fix bundle permissions ([#785ff82](https://github.com/snap-diff/snap_diff-capybara/commit/785ff82))

### Performance
- Eliminate array allocations in ChunkyPNG shift-detection ([#835f45b](https://github.com/snap-diff/snap_diff-capybara/commit/835f45b))
- Cache `without_tolerable_options?` at construction ([#b689ef5](https://github.com/snap-diff/snap_diff-capybara/commit/b689ef5))
- Memoize `Difference#region_area_size` ([#a3359dc](https://github.com/snap-diff/snap_diff-capybara/commit/a3359dc))
- Replace `method(:region_for)` with block in BrowserHelpers ([#324aafa](https://github.com/snap-diff/snap_diff-capybara/commit/324aafa))

### Documentation
- Add 60-second Quick Start to README top ([#61c7301](https://github.com/snap-diff/snap_diff-capybara/commit/61c7301))
- Add configuration tiers (zero-config / flaky / advanced) ([#50eb197](https://github.com/snap-diff/snap_diff-capybara/commit/50eb197))
- Add Troubleshooting section with 5 common problems ([#ac6d4e0](https://github.com/snap-diff/snap_diff-capybara/commit/ac6d4e0))
- Add Non-Rails setup, GitHub Actions integration, animation tip ([#b97f576](https://github.com/snap-diff/snap_diff-capybara/commit/b97f576))
- Add Quick Setup guide, tolerance table, and CI defaults note ([#786a0c1](https://github.com/snap-diff/snap_diff-capybara/commit/786a0c1))
- Add development guide for Docker testing and screenshot recording ([#8a7c981](https://github.com/snap-diff/snap_diff-capybara/commit/8a7c981))
- Add DeepWiki badge to README ([#0929cfa](https://github.com/snap-diff/snap_diff-capybara/commit/0929cfa))
- Document DEBUG in README ([#c1a53c3](https://github.com/snap-diff/snap_diff-capybara/commit/c1a53c3))

### Build/CI
- Upgrade dependencies for modern environment compatibility ([#d387627](https://github.com/snap-diff/snap_diff-capybara/commit/d387627))
- Improve dockerignore, gitignore, and fix bin/setup for Ruby 4.0 ([#674e854](https://github.com/snap-diff/snap_diff-capybara/commit/674e854))
- Bump actions/checkout from 4 to 5 ([#c5ad669](https://github.com/snap-diff/snap_diff-capybara/commit/c5ad669), [#eadc2aa](https://github.com/snap-diff/snap_diff-capybara/commit/eadc2aa))
- Bump actions/upload-artifact from 4 to 6 ([#3dbf8e9](https://github.com/snap-diff/snap_diff-capybara/commit/3dbf8e9), [#ab4fa48](https://github.com/snap-diff/snap_diff-capybara/commit/ab4fa48))
- Bump actions/cache from 4 to 5 ([#62419f7](https://github.com/snap-diff/snap_diff-capybara/commit/62419f7))
- Bump nick-fields/retry from 3 to 4 ([#b49f86a](https://github.com/snap-diff/snap_diff-capybara/commit/b49f86a))
- Pin minitest to < 6 to fix missing minitest/mock ([#4a65fd8](https://github.com/snap-diff/snap_diff-capybara/commit/4a65fd8))
- Re-record screenshot baselines for upgraded Chrome ([#de6e231](https://github.com/snap-diff/snap_diff-capybara/commit/de6e231))

### Internal Refactoring
- Inline `restore_git_revision` into `checkout_vcs` ([#9a4309c](https://github.com/snap-diff/snap_diff-capybara/commit/9a4309c))
- Replace implicit tuple protocol in ScreenshotAssertion ([#c078dec](https://github.com/snap-diff/snap_diff-capybara/commit/c078dec))
- Unify Screenshoter constructor to accept comparison_options ([#7845f88](https://github.com/snap-diff/snap_diff-capybara/commit/7845f88))
- Merge `build_null_comparison` into `build_null_difference` ([#676aa94](https://github.com/snap-diff/snap_diff-capybara/commit/676aa94))
- Flatten VipsUtil into VipsDriver class methods ([#9478f7f](https://github.com/snap-diff/snap_diff-capybara/commit/9478f7f))
- Inline ScreenshotNamerDSL into DSL module ([#1ffc36b](https://github.com/snap-diff/snap_diff-capybara/commit/1ffc36b))
- Inline `build_null_difference` in DifferenceFinder ([#2512ded](https://github.com/snap-diff/snap_diff-capybara/commit/2512ded))
- Consolidate skip_area accessor to Comparison ([#41f053a](https://github.com/snap-diff/snap_diff-capybara/commit/41f053a))
- Add bang to destructive Snap#cleanup_attempts! ([#2271126](https://github.com/snap-diff/snap_diff-capybara/commit/2271126))
- Remove duplicate `ensure_files_exist!` and unnecessary `options.dup` ([#b90509b](https://github.com/snap-diff/snap_diff-capybara/commit/b90509b))
- Remove redundant VipsDriver#dimension override ([#e670b58](https://github.com/snap-diff/snap_diff-capybara/commit/e670b58))
- Consolidate duplicate color constants and improve naming ([#2052d5f](https://github.com/snap-diff/snap_diff-capybara/commit/2052d5f))
- Replace `0.step` with loop in StableScreenshoter ([#b427499](https://github.com/snap-diff/snap_diff-capybara/commit/b427499))
- Remove duplicate require_relative in screenshot_matcher ([#b28f2eb](https://github.com/snap-diff/snap_diff-capybara/commit/b28f2eb))

---

## [v1.11.0] - Previous Release

[Unreleased]: https://github.com/snap-diff/snap_diff-capybara/compare/v1.12.0...HEAD
[v1.12.0]: https://github.com/snap-diff/snap_diff-capybara/releases/tag/v1.12.0
[v1.11.0]: https://github.com/snap-diff/snap_diff-capybara/releases/tag/v1.11.0

**Upgrade Guide:** See [docs/UPGRADING.md](docs/UPGRADING.md) for detailed migration instructions.
