# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.15.0] - 2026-08-22

### Added
- **`SnapDiff::Config`** — one flat object consolidating all 27 settings behind `SnapDiff.config` / `SnapDiff.configure { |config| ... }`; purely additive, the existing accessors stay canonical and both views share one source of truth ([#200](https://github.com/snap-diff/snap_diff-capybara/pull/200))

### Fixed
- **`pending_if_new` no longer masks real failures** — a raising Minitest `teardown` or a raising RSpec `after` hook registered before the gem could previously be reported as a skipped/pending test with exit 0; the pending marker now defers until the framework's teardown chain has run and yields to any failure. Known residual: an RSpec `config.append_after` registered after this gem still runs later than the gem's hook — require the gem last if you use appended after-hooks ([#203](https://github.com/snap-diff/snap_diff-capybara/pull/203))
- **`BacktraceFilter` path-boundary matching** — a custom `lib_directory` of `/app/lib` no longer also filters locations under `/app/library` ([#202](https://github.com/snap-diff/snap_diff-capybara/pull/202))

### Internal
- Failure-masking guard tests for the `pending_if_new` teardown paths via subprocess RSpec runs ([#199](https://github.com/snap-diff/snap_diff-capybara/pull/199))
- Hygiene pass — skip-area/VCS-baseline and `BacktraceFilter` guard tests, entry-point forwarder dedupe, `Comparison` and `BacktraceFilter` merged into their sole consumers (−2 files, constant paths preserved) ([#201](https://github.com/snap-diff/snap_diff-capybara/pull/201))

---

## [v1.14.0] - 2026-08-22

### Added
- **`SnapDiff` namespace aliases** — `SnapDiff::Comparison`, `SnapDiff.compare`, and `SnapDiff.start` provide a forward-looking entry point onto the existing `Capybara::Screenshot::Diff` API, no behavior changes ([#166](https://github.com/snap-diff/snap_diff-capybara/issues/166))

### Fixed
- **Standalone require path** — `require "capybara_screenshot_diff"` (or `require "snap_diff"`) followed by `Diff.compare` no longer raises `NameError` for the missing drivers require ([#194](https://github.com/snap-diff/snap_diff-capybara/pull/194))

### Internal
- Merged `DifferenceFinder` into `ImageCompare` (ADR-004 step) ([#192](https://github.com/snap-diff/snap_diff-capybara/pull/192))
- Extracted `AnnotationService` from `Reporters::Default`; full public surface preserved via delegation ([#193](https://github.com/snap-diff/snap_diff-capybara/pull/193))
- Consolidated `pending_if_new` teardown logic into one shared helper across Minitest/RSpec/Cucumber adapters ([#197](https://github.com/snap-diff/snap_diff-capybara/pull/197))
- Test-suite driver-coverage banner and CI guard against silently missing drivers ([#198](https://github.com/snap-diff/snap_diff-capybara/pull/198))

---

## [v1.13.0] - 2026-08-22

### Added
- **`capture_screenshot` DSL method** — take a screenshot without ever comparing or asserting ([#191](https://github.com/snap-diff/snap_diff-capybara/issues/191))
- **`compare:` option on `screenshot`** — pass `compare: true` (default) to assert, or `compare: false` to capture only ([#191](https://github.com/snap-diff/snap_diff-capybara/issues/191))
- **`Capybara::Screenshot::Diff.pending_if_new` config** — mark tests as skipped in teardown when a baseline does not exist, complementing `fail_if_new` ([#191](https://github.com/snap-diff/snap_diff-capybara/issues/191))

### Changed
- **`assert_matches_screenshot` is now the primary assertion method** — captures a screenshot and compares against baseline ([#191](https://github.com/snap-diff/snap_diff-capybara/issues/191))
- **`screenshot` is now a convenience wrapper** — safe to override in user test classes; the gem no longer calls it internally ([#191](https://github.com/snap-diff/snap_diff-capybara/issues/191))

---

## [v1.12.0] - 2026-04-12

### Added
- **HTML reporter** — interactive dashboard with 4 comparison modes (both/base/new/heatmap), per-image zoom, keyboard navigation, and search ([#170](https://github.com/snap-diff/snap_diff-capybara/pull/170))
- **GitHub Actions integration** — inline HTML preview with base64 embedded images + reusable composite action ([#171](https://github.com/snap-diff/snap_diff-capybara/pull/171))
- **`disable_animations` helper** — inject CSS to stop all animations/transitions during screenshots ([#174](https://github.com/snap-diff/snap_diff-capybara/pull/174))
- **`snap_diff:clean` rake task** — remove diff artifacts while keeping baselines ([#177](https://github.com/snap-diff/snap_diff-capybara/pull/177))
- `Diff.compare` for standalone image comparison without Capybara or browser
- Perceptual color distance (dE00) for anti-aliasing tolerance in VipsDriver
- `assert_no_screenshot_changes` DSL assertion
- `Diff.configure` block helper for simplified configuration
- Ruby 3.5 and 4.0 support

### Changed
- `blur_active_element` now defaults to `true` — prevents cursor blinking artifacts
- `hide_caret` now defaults to `true` — stable screenshots without caret
- `fail_if_new` now defaults to `true` in CI (when `ENV['CI']` is set)
- Thread-safe reporter notification with mutex ([#175](https://github.com/snap-diff/snap_diff-capybara/pull/175))

### Removed
- **SVN support** — Git only
- **ActiveSupport runtime dependency** — pure Ruby, lighter installations

### Fixed
- VCS path resolution rewritten for thread safety (Open3 + array-form system)
- Reporter diff artifacts cleaned up properly on `Snap#delete!` ([#173](https://github.com/snap-diff/snap_diff-capybara/pull/173))
- RSpec matcher now provides `failure_message` and description
- Missing baseline error includes recording instructions
- Ruby 4.0 DSLStub ordering compatibility
- ChunkyPNG `filter_image_with_median` incorrect behavior
- Tolerance calculation no longer skips large changes

### Performance
- ChunkyPNG shift-detection: eliminated array allocations (~30% faster for large images)
- VIPS: cached computations at construction (~15% faster)
- Memoized region area size, replaced closures with blocks

### Documentation
- README restructured from 970 to 149 lines with 7 dedicated `docs/` files ([#171](https://github.com/snap-diff/snap_diff-capybara/pull/171))
- CI integration guide with artifact upload and PR commenting ([docs/ci-integration.md](docs/ci-integration.md))
- Upgrade guide ([docs/UPGRADING.md](docs/UPGRADING.md))
- Color comparison guide — tolerance vs perceptual_threshold vs color_distance_limit ([#176](https://github.com/snap-diff/snap_diff-capybara/pull/176))

### Internal
- Simplified internals: inlined CaptureStrategy, ComparisonLoader, ScreenshotNamerDSL, VipsUtil
- Unified Screenshoter constructors, consolidated skip_area accessor
- Upgraded CI dependencies (actions/checkout v5, upload-artifact v7)

---

## [v1.11.0] - Previous Release

[Unreleased]: https://github.com/snap-diff/snap_diff-capybara/compare/v1.12.0...HEAD
[v1.12.0]: https://github.com/snap-diff/snap_diff-capybara/releases/tag/v1.12.0
[v1.11.0]: https://github.com/snap-diff/snap_diff-capybara/releases/tag/v1.11.0

**Upgrade Guide:** See [docs/UPGRADING.md](docs/UPGRADING.md) for detailed migration instructions.
