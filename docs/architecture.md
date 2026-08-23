# Architecture

This document describes the internal architecture of the gem — how screenshots are captured, compared, and reported, and how the components fit together.

The implementation lives in `lib/snap_diff/` under the `SnapDiff` namespace, and since 2.1 that is the only namespace: the v1 file trees (`lib/capybara/screenshot/diff/`, `lib/capybara_screenshot_diff/`), the `legacy_shims.rb` that resolved their constants, and the deprecation machinery around them were deleted. 34 files ship under `lib/`, listed in [File Layout](#file-layout) below. Class names below are the canonical ones, with the v1 name noted in passing where the history explains a shape. For the user-facing view of the same surface, see [SnapDiff — the canonical API](snapdiff.md).

## Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Test Framework                         │
│  (Minitest / RSpec / Cucumber / Custom)                  │
└──────────────┬──────────────────────────────┬────────────┘
               │                              │
               ▼                              ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│  SnapDiff::DSL            │    │  SnapDiff::AssertionRegistry│
│  (screenshot, etc)        │    │  (SnapDiff.session)        │
└──────────────┬───────────┘    └──────────────┬───────────┘
               │                               │
               ▼                               ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│  ScreenshotMatcher        │    │  ScreenshotAssertion     │
│  (capture + compare)      │    │  (validate results)      │
└──────┬───────────┬────────┘    └──────────────┬───────────┘
       │           │                            │
       ▼           ▼                            ▼
┌──────────┐ ┌──────────┐           ┌──────────────────────┐
│Screenshot│ │Stable    │           │   Reporters           │
│er        │ │Screenshot│           │  (Default / HTML /    │
│          │ │er        │           │   Custom)             │
└─────┬────┘ └──────────┘           └──────────────────────┘
      │
      ▼
┌──────────────────────────────────────────┐
│  SnapDiff::Comparison (layered compare)  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │1. Byte   │ │2. Pixel  │ │3. Region │  │
│  │  compare │ │  compare │ │  analyze │  │
│  └──────────┘ └──────────┘ └──────────┘  │
└─────────────────────┬────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────┐
│  VipsDriver (the image backend)          │
│  ┌────────────────────────────────────┐  │
│  │ libvips via ruby-vips              │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

## Component Breakdown

### 1. DSL Layer (`lib/snap_diff/dsl.rb`)

The entry point for test code. `assert_matches_screenshot` is the primary assertion method (captures and compares). `screenshot` is a convenience wrapper with a `compare:` option — `compare: true` (default) delegates to `assert_matches_screenshot`, while `compare: false` delegates to the new `capture_screenshot` method. `capture_screenshot` takes screenshots without assertions. `assert_no_screenshot_changes` keeps its behavior but now delegates to `assert_matches_screenshot` (that redirect is part of the #191 fix). Users can safely override `screenshot` in their test classes without affecting internal gem flow.

**Flow:**
1. Checks if screenshots are `active?` (returns `false` if disabled)
2. Builds a full screenshot name via `ScreenshotNamer` (handles sections, groups, counters)
3. Delegates to `ScreenshotMatcher` to capture and prepare comparison
4. Creates a `ScreenshotAssertion` — either adds it to the thread-local registry (delayed validation) or validates immediately

### 2. ScreenshotMatcher (`lib/snap_diff/screenshot_matcher.rb`)

The orchestrator that coordinates capture and comparison:

1. **Viewport preparation** — `SnapDiff::Capture::Viewport.prepare!` (`lib/snap_diff/capture/viewport.rb`) verifies the browser window is the expected size (raise-only, never resizes); runs once per capture, outside any stability retry loop
2. **Area calculation** — resolves crop regions and skip areas (supports CSS selectors and coordinates)
3. **Base screenshot checkout** — retrieves the committed baseline from git via `Vcs.checkout_vcs`
4. **Capture** — delegates to `Screenshoter` or `StableScreenshoter` depending on `stability_time_limit`
5. **Comparison** — creates a `SnapDiff::Comparison` object (lazy — actual comparison happens on first access)
6. **Assertion** — returns a `ScreenshotAssertion` with the comparison attached

**Key design decision:** The "new" screenshot is taken *first*, then compared against the baseline. This means if no baseline exists (first run), we skip comparison entirely and the test passes.

### 3. Screenshoter & StableScreenshoter (`lib/snap_diff/screenshoter.rb`, `lib/snap_diff/stable_screenshoter.rb`)

**Screenshoter:** The basic capture flow:
1. Prepares the page (blur active element, hide caret, disable animations, wait for images)
2. Takes a browser screenshot via `Capybara.current_session.save_screenshot`
3. Processes the screenshot (resize for retina, apply crop)

**StableScreenshoter:** Wraps `Screenshoter` with stability detection:
1. Takes sequential screenshots at `stability_time_limit` intervals
2. Compares consecutive attempts for byte-level equality
3. Returns once two consecutive screenshots are identical
4. Fails with `UnstableImage` if timeout (`wait`) is reached, generating annotated attempt images for debugging

### 4. Comparison (`lib/snap_diff/comparison.rb`)

`SnapDiff::Comparison` (v1 name: `ImageCompare`); its result value object is `SnapDiff::ComparisonResult` (`lib/snap_diff/comparison_result.rb`, v1 name: `Difference`).

The comparison engine uses a **layered optimization strategy** to balance speed and accuracy:

| Layer | Method | What it checks | Speed | When it returns |
|-------|--------|----------------|-------|-----------------|
| 1 | `quick_equal?` | File size + byte-level comparison | Fastest | Equal → `true`, Different → Layer 2 |
| 2 | `quick_equal?` continues | Dimension check + pixel comparison | Fast | Different dimensions → `false`, Same pixels → `true` |
| 3 | `processed` / `different?` | Full region analysis with tolerance | Slower | Detailed diff with region, heatmap, annotations |

**Key details:**
- `quick_equal?` is designed for fast rejection — it early-returns as soon as a difference is found
- `different?` triggers the full comparison if not already processed
- `processed` guarantees the comparison is complete and returns the result with all metadata
- `Comparison#analyze_difference` handles the actual pixel analysis, delegating to the driver

### 5. The image backend (`lib/snap_diff/drivers/vips_driver.rb`)

`SnapDiff::Drivers::VipsDriver` does the image work. 2.1 removed the abstraction that used to sit around it — the `SnapDiff::Driver` mixin, the `SnapDiff::Drivers` registry (`.loaded` / `.available` / `.for` / `.detect_available`), the `driver:` setting and `driver: :auto`. `ruby-vips` is a gemspec runtime dependency, so there is nothing to detect and nothing to select; `Comparison` and `Screenshoter` each construct a `VipsDriver` directly (it is stateless). `Drivers` survives only as the namespace the class is published under.

| Operation | VipsDriver |
|-----------|-----------|
| `load_images` | `Vips::Image` from file |
| `same_dimension?` | Compare width × height |
| `same_pixels?` | Pixel-level equality |
| `find_difference_region` | Difference mask → Region |
| `crop` | Vips image crop |
| `save_image_to` | Vips `write_to_file` |
| `filter_image_with_median` | Vips median filter |
| `add_black_box` | Draw filled rect |
| `merge` | Composite images |
| `highlight_mask` | Conditional color overlay |

**Loader cache:** `#from_file` passes `revalidate: true`. libvips caches loader operations on filename + mtime, and mtime has one-second resolution — without this, rewriting a screenshot path and re-reading it within the same second serves the PREVIOUS image. See the regression test in `test/unit/drivers/vips_driver_test.rb`.

There is no custom-driver path; see [SnapDiff — the canonical API](snapdiff.md) and [Image Processing](drivers.md).

### 6. Difference Region Detection

`VipsDriver` uses a **difference mask** approach:
1. Compute absolute difference between images: `(new - base).abs`
2. Optional: apply perceptual color distance (CIE dE00) instead of raw RGB
3. Project the mask to find the bounding region of non-zero pixels
4. Return the tight bounding box of all differences

### 7. SnapManager & Snap (`lib/snap_diff/snap_manager.rb`, `lib/snap_diff/snap.rb`)

**Snap** represents a single screenshot file with path management:
- `path` — the actual screenshot file
- `base_path` — the `.base.ext` VCS checkout
- `attempt_path` — stability attempt files (`.attempt_00.png`, etc.)
- Provides cleanup of diff artifacts (`.diff.png`, `.heatmap.diff.png`)

**SnapManager** is the factory and path manager:
- Creates `Snap` instances
- Handles VCS checkout of baselines
- Manages file operations (copy, move, cleanup)

### 8. VCS (`lib/snap_diff/vcs.rb`)

Handles baseline retrieval from git. Uses `git show HEAD:<path>` to extract the committed version. Supports Git LFS via `git lfs smudge`. Returns `false` if the file doesn't exist in VCS (first-run scenario).

### 9. Reporters (`lib/snap_diff/reporters/default.rb`, `lib/snap_diff/reporters/html.rb`)

**Default reporter:** Generates annotated diff images:
- `image.diff.png` — new screenshot with diff region outlined in red
- `image.base.diff.png` — baseline with diff region outlined in red
- `image.heatmap.diff.png` — heatmap overlay of pixel differences

**HTML reporter:** Generates an interactive dashboard (`snap_diff_report.html`) with:
- Sidebar with thumbnails and search
- 4 view modes (both/base/new/heatmap)
- Annotated toggle for showing diff outlines
- Per-image zoom with synchronized panning across side-by-side views
- Keyboard navigation and shortcuts
- Responsive layout for mobile

**Custom reporters:** Implement `record(assertions)`, `finalize` and `summary`, then register via `SnapDiff::Reporting.register(reporter)` — the way in, because the append happens under the mutex. The process-global reporter lifecycle (registration, notification, finalization) is owned by `SnapDiff::Reporting` (`lib/snap_diff/reporting.rb`); `SnapDiff::Reporting.reporters` stays a mutable array (appending directly still works, it just skips the lock). See [Custom reporters](snapdiff.md#custom-reporters).

### 10. Assertion Lifecycle

```
Test begins
    │
    ├─ setup: resize_window_if_needed
    │
    ├─ test body:
    │    └─ screenshot("name")
    │         ├─ ScreenshotMatcher builds assertion
    │         ├─ delayed=true → add to Thread-local registry
    │         └─ delayed=false → validate immediately
    │
    ├─ teardown:
    │    ├─ SnapDiff.session.verify
    │    │    ├─ iterates the fiber-local assertions
    │    │    ├─ calls validate on each
    │    │    └─ raises SnapDiff::ExpectationNotMet if any differed
    │    │
    │    └─ SnapDiff.reset (always, in an ensure)
    │         ├─ SnapDiff::Reporting.notify — mutex-protected reporter snapshot
    │         └─ clears the session
    │
    └─ end of suite (Minitest.after_run / RSpec after(:suite) / Cucumber AfterAll):
         └─ SnapDiff::Reporting.finalize!
              ├─ Generates HTML report (if reporter registered)
              └─ Prints each reporter's summary
```

### 11. Thread Safety

| Concern | Mechanism |
|---------|-----------|
| Assertion registry | Thread-local storage (`Thread.current[:capybara_screenshot_diff_registry]`) |
| Reporter notification | Mutex-protected snapshot of reporter list before iteration |
| HTML reporter internals | Mutex protecting `@failures`, `@total`, `@finalized` |
| Screenshot naming | Per-thread `ScreenshotNamer` instance |
| Global configuration | One process-wide `SnapDiff::Config` instance — must be set before tests run, not mutated during parallel execution |
| File system | Atomic `FileUtils.mv`, unique paths per screenshot name + counter, thread-safe `mkpath` |

### 12. Configuration System

Since ADR-008 step 1 the storage ownership is inverted from the original v2 consolidation: **`SnapDiff::Config` (`lib/snap_diff/config.rb`) IS the storage** — one eagerly-created instance, reachable as `SnapDiff.config`, holding every setting as a plain `attr_accessor`. It is the leaf of the config require graph and requires nothing that leads back to either entry point.

2.1 removed the second view. `lib/snap_diff/legacy_shims.rb` — the single file that held the v1 surface as code (the `const_missing` forwarders, `CONFIG_MAPPING` and its delegator generator, the derived forwarders, `SnapDiff.start`) — is deleted, along with `lib/capybara/screenshot/diff/config_legacy.rb`. `Config` declares its settings in `Config::SETTINGS` and nothing maps them onto anything else.

All 25 are flat on one object; `Config::SETTINGS` still declares them in two informal groups, capture first and comparison second:

**Capture (13):** `add_driver_path`, `add_os_path`, `blur_active_element`, `screenshot_enabled`, `hide_caret`, `disable_animations`, `root`, `stability_time_limit`, `window_size`, `save_path`, `use_lfs`, `screenshot_format`, `capybara_screenshot_options`

**Comparison (12):** `delayed`, `area_size_limit`, `fail_if_new`, `pending_if_new`, `fail_on_difference`, `color_distance_limit`, `enabled`, `skip_area`, `tolerance`, `perceptual_threshold`, `screenshoter`, `manager`

`SnapDiff.configure { |config| ... }` is the only block form — the two-holder shape (`SnapDiff.start`, `Capybara::Screenshot::Diff.configure`) went with the holders it yielded. `screenshot_enabled` is the one setting whose name differs from its v1 spelling, because a flat object cannot carry two attributes called `enabled`.

`Config` also owns the derived values that used to live on the v1 modules: `active?` (ex `Capybara::Screenshot.active?`, which reads both `enabled` flags), `screenshot_area` / `screenshot_area_abs`, and `default_options` (ex `Capybara::Screenshot::Diff.default_options`, the option hash handed to `SnapDiff::Comparison`).

**Default timing contract:** every default is evaluated once, in `Config#initialize`, which runs at require time of `config.rb` — the same load moment the old `mattr_accessor` default blocks evaluated at. `fail_if_new` (from `ENV["CI"]`) and `root` (from `Rails.root`) must never become lazy read-time defaults. The one deliberately live value is `default_options[:wait]`, a method-body read of `Capybara.default_max_wait_time`.

## File Layout

All 34 packaged files, one namespace:

```
lib/
  snap_diff.rb                                 # SnapDiff module: compare/configure/config
  snap_diff-capybara.rb                        # Bundler auto-require entry for gem "snap_diff-capybara"
  snap_diff/
    dsl.rb                                     # screenshot(), screenshot_group(), etc.
    config.rb                                  # SnapDiff::Config — THE storage for all 25 settings
    errors.rb                                  # Error / ExpectationNotMet / UnstableImage / WindowSizeMismatchError
    error_with_filtered_backtrace.rb           # Error with filtered stack
    region.rb                                  # SnapDiff::Region — bounding box
    comparison.rb                              # Layered comparison engine (ex-ImageCompare)
    comparison_result.rb                       # Comparison result value object (ex-Difference)
    drivers/
      vips_driver.rb                           # THE image backend (libvips)
    capture/
      viewport.rb                              # Per-capture viewport preparation seam
    screenshoter.rb                            # Basic browser screenshot capture
    stable_screenshoter.rb                     # Stability detection wrapper
    screenshot_matcher.rb                      # Orchestrator for capture + compare
    screenshot_assertion.rb                    # Assertion + registry objects, session lifecycle
    screenshot_namer.rb                        # Name/path generation with sections/groups
    snap_manager.rb                            # Screenshot file management
    snap.rb                                    # Single screenshot file abstraction
    reporting.rb                               # Process-global reporter lifecycle
    reporters/
      default.rb                               # Annotated diff images + failure message
      html.rb                                  # Interactive HTML report reporter
      templates/report.html.erb                # HTML report template
    annotation_service.rb                      # Diff-image annotation (RED_RGBA / ORANGE_RGBA)
    image_preprocessor.rb                      # Pre-processing (skip areas, median filter)
    area_calculator.rb                         # Crop/skip area coordinate resolution
    browser_helpers.rb                         # DOM manipulation helpers
    attempts_reporter.rb                       # Debug reporting for unstable captures
    vcs.rb                                     # Git baseline checkout
    os.rb                                      # OS detection
    static.rb                                  # Non-Rails static site serving
    version.rb                                 # Gem version (the gemspec reads it)
    integrations/
      minitest.rb                              # Minitest assertions integration
      rspec.rb                                 # RSpec matcher integration
      cucumber.rb                              # Cucumber World integration
```

Gone in 2.1, and worth knowing if you are reading an older commit or an old stack trace: `lib/capybara_screenshot_diff.rb` and its tree, `lib/capybara/screenshot/diff.rb` and its tree, `snap_diff/legacy_shims.rb`, `snap_diff/deprecation.rb`, `snap_diff/removal.rb`, `snap_diff/driver.rb`, `snap_diff/drivers.rb` (the registry — `drivers/` survives as a directory holding one class), `snap_diff/drivers/chunky_png_driver.rb` and `snap_diff/utils.rb` (driver detection).

See [SnapDiff — the canonical API](snapdiff.md) for the canonical surface, and [UPGRADING.md](UPGRADING.md) for the migration guide.
