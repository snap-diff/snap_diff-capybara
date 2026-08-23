# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v2.0.0.beta2] - 2026-08-23

Third prerelease of the 2.0 opt-in experiment. This one finishes the namespace
move: `SnapDiff` no longer depends on the namespaces it deprecates. Legacy names
keep working exactly as before — see the v2.0.0.alpha1 notes below for the
opt-in and silencing basics, and [docs/snapdiff.md](docs/snapdiff.md) for the
canonical API.

### Changed
- **Everything canonical now lives in `SnapDiff`** — configuration storage
  (`SnapDiff::Config`, one storage behind every settings surface), error classes
  (`SnapDiff::Error`, `ExpectationNotMet`, `UnstableImage`,
  `WindowSizeMismatchError`), `SnapDiff::Region`, `SnapDiff::Reporters::Default`,
  the driver registry (`SnapDiff::Drivers.loaded`/`.available`), the per-test
  session (`SnapDiff.session`), and reporter registration
  (`SnapDiff::Reporting.register`, mutex-guarded). Old constants remain
  same-object aliases; `rescue`, `is_a?`, and `defined?` on them are unchanged
  ([#224](https://github.com/snap-diff/snap_diff-capybara/pull/224)–[#230](https://github.com/snap-diff/snap_diff-capybara/pull/230))
- **Error class names in failure output** now print as `SnapDiff::…` (the class
  objects are identical, so `rescue CapybaraScreenshotDiff::ExpectationNotMet`
  still catches them — only the printed name differs). CI jobs that
  string-match on the old class name in output need updating.
- The images-holder struct is now `SnapDiff::Comparison::Images`, ending the
  two-classes-one-name collision with the comparator
  ([#227](https://github.com/snap-diff/snap_diff-capybara/pull/227))

### Added
- **Deprecation warnings now name your call site** — `(called from
  your_file.rb:42)`, so migration is warning-driven instead of grep-driven
  ([#222](https://github.com/snap-diff/snap_diff-capybara/pull/222))
- **Dual-install guard** — installing both `capybara-screenshot-diff` and
  `snap_diff-capybara` now raises a clear error instead of silently loading
  files from whichever gem activated first
  ([#222](https://github.com/snap-diff/snap_diff-capybara/pull/222))
- **[docs/snapdiff.md](docs/snapdiff.md)** — the SnapDiff-native guide: quick
  start for all four integrations, configuration, custom drivers and reporters,
  standalone comparison ([#231](https://github.com/snap-diff/snap_diff-capybara/pull/231))

### Removed
- The unused `anchor:` keyword on the internal viewport seam; v3's
  scroll-preservation work will design its real contract
  ([#229](https://github.com/snap-diff/snap_diff-capybara/pull/229))

### Internal
- A test now mechanically enforces that the legacy namespace trees contain only
  requires, aliases, and one-line forwarders — no real logic — so removing them
  in 3.0 is a deletion, not a refactor
  ([#229](https://github.com/snap-diff/snap_diff-capybara/pull/229),
  [#230](https://github.com/snap-diff/snap_diff-capybara/pull/230))
- Release workflow is idempotent on re-run; config default-eval timing is
  pinned by guards across every entry point
  ([#222](https://github.com/snap-diff/snap_diff-capybara/pull/222),
  [#223](https://github.com/snap-diff/snap_diff-capybara/pull/223))

---

## [v2.0.0.beta1] - 2026-08-22

Second prerelease of the 2.0 opt-in experiment (see the v2.0.0.alpha1 notes
below for the namespace change, deprecation warnings, and caveats). Final
2.0.0 remains gated on adopter feedback — [#166](https://github.com/snap-diff/snap_diff-capybara/issues/166).

### Added
- **Dual gem names** — releases now also publish as
  [`snap_diff-capybara`](https://rubygems.org/gems/snap_diff-capybara):
  identical content and versions under the forward-looking name matching this
  repository (the alpha1 mirror was backfilled). Install either, not both.
- **Migration guide** — [docs/UPGRADING.md](docs/UPGRADING.md) covers the v2
  namespace move, every renamed constant, silencing, and the alpha caveats
  ([#220](https://github.com/snap-diff/snap_diff-capybara/pull/220))

### Internal
- Test suite exercises the canonical `SnapDiff` names; legacy names remain
  covered by dedicated forwarding/deprecation tests, and a strict warning
  guard now fails the suite on any accidental legacy-name use
  ([#221](https://github.com/snap-diff/snap_diff-capybara/pull/221))

---

## [v2.0.0.alpha1] - 2026-08-22

**Opt-in experiment prerelease.** RubyGems never installs prereleases by default
resolution — to try it: `gem "capybara-screenshot-diff", "2.0.0.alpha1"`. The
final 2.0.0 ships only after adopter feedback on this train; please report
anything surprising on [#166](https://github.com/snap-diff/snap_diff-capybara/issues/166).

### Changed
- **`SnapDiff` is the canonical namespace.** The implementation lives in
  `lib/snap_diff/`; every legacy constant (`Capybara::Screenshot::Diff::*`,
  `CapybaraScreenshotDiff::*`) still resolves to the *same object* and keeps
  working ([#208](https://github.com/snap-diff/snap_diff-capybara/pull/208),
  [#209](https://github.com/snap-diff/snap_diff-capybara/pull/209),
  [#210](https://github.com/snap-diff/snap_diff-capybara/pull/210)):
  `ImageCompare` → `SnapDiff::Comparison`, `Difference` →
  `SnapDiff::ComparisonResult`, `Drivers::BaseDriver` → `SnapDiff::Driver` (mixin).
- **Legacy constants warn on first use** — once per constant per process, naming
  the replacement ([#218](https://github.com/snap-diff/snap_diff-capybara/pull/218)).
  Silence with `SnapDiff.silence_deprecations = true` or
  `SNAP_DIFF_SILENCE_DEPRECATIONS=1`. A few constants stay silent by design
  (`Os`, `DSL`, `VERSION`, driver leaf classes — see `lib/snap_diff/legacy_shims.rb`).

### Fixed
- Annotation color constants resolve under the bare `require "snap_diff"` entry;
  previously a differing comparison raised `NameError` there
  ([#219](https://github.com/snap-diff/snap_diff-capybara/pull/219))

### Known caveats (deliberate, alpha)
- `defined?(...)` / `const_defined?` on lazily-shimmed legacy names returns
  false/nil — feature detection like `defined?(Capybara::Screenshot::Diff::Drivers::VipsDriver)`
  must move to the `SnapDiff::` name. Rescuing legacy error classes is unaffected
  (they remain eagerly defined).
- Reopening `module Capybara::Screenshot::Diff::Drivers` (historical custom-driver
  monkey-patch pattern) defines a fresh module that shadows the shim; define custom
  drivers under `SnapDiff::Drivers` instead.

### Internal
- Core simplification, behavior-preserving (the "5.5-lite" pass): pure
  capture/comparison option partition ([#212](https://github.com/snap-diff/snap_diff-capybara/pull/212)),
  stability failure as data ([#213](https://github.com/snap-diff/snap_diff-capybara/pull/213)),
  explicit `ScreenshotAssertion#archive_baseline!` + `#inspect` on
  assertion/result ([#214](https://github.com/snap-diff/snap_diff-capybara/pull/214)),
  `SnapDiff::Capture::Viewport` seam with the future `anchor:` hook
  ([#215](https://github.com/snap-diff/snap_diff-capybara/pull/215)), reporter vs
  session lifecycle separation ([#216](https://github.com/snap-diff/snap_diff-capybara/pull/216)),
  all behind a guard-test net ([#211](https://github.com/snap-diff/snap_diff-capybara/pull/211))

---

## [v1.15.1] - 2026-08-22

### Fixed
- **`VipsDriver#resize_image_to` resizes to the requested dimensions** — the vips driver passed a target aspect ratio where libvips expects a scale factor, so retina-halving on macOS/Selenium could enlarge screenshots (2560×1600 → 4096×2560) and save wrongly-sized baselines; now scales width and height independently via `resize(scale, vscale:)` ([#205](https://github.com/snap-diff/snap_diff-capybara/pull/205))

### Internal
- Driver contract tests pinning the shared ChunkyPNG/Vips driver seam (method surface, load/compare behavior, option handling) — the net that caught the resize bug ([#204](https://github.com/snap-diff/snap_diff-capybara/pull/204))

---

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
