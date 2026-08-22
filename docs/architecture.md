# Architecture

This document describes the internal architecture of `capybara-screenshot-diff` — how screenshots are captured, compared, and reported, and how the components fit together.

Since the v2 namespace move (ADR-004), the implementation lives in `lib/snap_diff/` under the `SnapDiff` namespace. The old file paths (`lib/capybara/screenshot/diff/`, `lib/capybara_screenshot_diff/`) remain as thin forwarders, and the old constants resolve to the same objects via `lib/snap_diff/legacy_shims.rb` with a one-time deprecation warning. Class names below use the canonical `SnapDiff::` names, with legacy names noted where they differ.

## Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Test Framework                         │
│  (Minitest / RSpec / Cucumber / Custom)                  │
└──────────────┬──────────────────────────────┬────────────┘
               │                              │
               ▼                              ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│  CapybaraScreenshotDiff   │    │  CapybaraScreenshotDiff   │
│  ::DSL (screenshot, etc)  │    │  ::AssertionRegistry       │
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
│  Drivers (image processing backends)     │
│  ┌──────────┐ ┌──────────────────────┐   │
│  │ Vips     │ │ ChunkyPNG            │   │
│  │ (fast)   │ │ (no native deps)     │   │
│  └──────────┘ └──────────────────────┘   │
└──────────────────────────────────────────┘
```

## Component Breakdown

### 1. DSL Layer (`lib/snap_diff/dsl.rb`)

`SnapDiff::DSL` — `CapybaraScreenshotDiff::DSL` remains an eager same-object alias.

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

`SnapDiff::Comparison` (legacy name: `ImageCompare`); its result value object is `SnapDiff::ComparisonResult` (`lib/snap_diff/comparison_result.rb`, legacy name: `Difference`).

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

### 5. Drivers (`lib/snap_diff/drivers/`)

Drivers abstract image processing operations. Shared default behavior lives in the `SnapDiff::Driver` mixin (`lib/snap_diff/driver.rb`) — it replaced the old `Drivers::BaseDriver` superclass, so concrete drivers `include SnapDiff::Driver` instead of inheriting. Each driver implements:

| Operation | VipsDriver | ChunkyPNGDriver |
|-----------|-----------|-----------------|
| `load_images` | Vips::Image from file | ChunkyPNG::Image from blob |
| `same_dimension?` | Compare width × height | Same |
| `same_pixels?` | Pixel-level equality | Same |
| `find_difference_region` | Difference mask → Region | Row-by-row scan → Region |
| `crop` | Vips image crop | ChunkyPNG crop |
| `save_image_to` | Vips write_to_file | PNG save |
| `filter_image_with_median` | Vips median filter | Not supported |
| `add_black_box` | Draw filled rect | No-op (handled differently) |
| `merge` | Composite images | Not applicable |
| `highlight_mask` | Conditional color overlay | Not applicable |

**Auto-detection:** `Utils.detect_available_drivers` tries to load `:vips` first (via `ruby-vips` gem), then `:chunky_png`. The `:auto` driver mode picks the first available.

### 6. Difference Region Detection

**VipsDriver** uses a **difference mask** approach:
1. Compute absolute difference between images: `(new - base).abs`
2. Optional: apply perceptual color distance (CIE dE00) instead of raw RGB
3. Project the mask to find the bounding region of non-zero pixels
4. Return the tight bounding box of all differences

**ChunkyPNGDriver** uses **row-by-row scanning**:
1. Scan top-to-bottom, left-to-right for first differing pixel
2. Expand left/right boundaries within each differing row
3. Extend bottom boundary to cover all differing rows
4. Supports shift detection (expensive neighbor pixel search)

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

**Custom reporters:** Implement `record(assertions)` and `finalize` methods, then add to `CapybaraScreenshotDiff.reporters`. The process-global reporter lifecycle (registration, notification, finalization) is owned by `SnapDiff::Reporting` (`lib/snap_diff/reporting.rb`); `CapybaraScreenshotDiff.reporters` / `.finalize_reporters!` are thin public shims over it.

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
    │    └─ CapybaraScreenshotDiff.verify
    │         ├─ iterates thread-local assertions
    │         ├─ calls validate on each
    │         ├─ raises ExpectationNotMet on first failure
    │         └─ notifies reporters via mutex-protected snapshot
    │
    └─ at_exit:
         └─ CapybaraScreenshotDiff.finalize_reporters!
              ├─ Generates HTML report (if reporter registered)
              └─ Prints summary
```

### 11. Thread Safety

| Concern | Mechanism |
|---------|-----------|
| Assertion registry | Thread-local storage (`Thread.current[:capybara_screenshot_diff_registry]`) |
| Reporter notification | Mutex-protected snapshot of reporter list before iteration |
| HTML reporter internals | Mutex protecting `@failures`, `@total`, `@finalized` |
| Screenshot naming | Per-thread `ScreenshotNamer` instance |
| Global configuration | `mattr_accessor` — must be set before tests run, not mutated during parallel execution |
| File system | Atomic `FileUtils.mv`, unique paths per screenshot name + counter, thread-safe `mkpath` |

### 12. Configuration System

Configuration uses Ruby's `mattr_accessor` (pure Ruby implementation in `lib/capybara/screenshot/diff/config_legacy.rb`, deliberately kept at the old path as the single source of truth for settings storage) and is organized into two namespaces:

**`Capybara::Screenshot`** — capture settings:
- `window_size`, `stability_time_limit`, `blur_active_element`, `hide_caret`, `disable_animations`
- `save_path`, `root`, `screenshot_format`, `add_driver_path`, `add_os_path`
- `enabled`, `capybara_screenshot_options`

**`Capybara::Screenshot::Diff`** — comparison settings:
- `driver`, `tolerance`, `color_distance_limit`, `perceptual_threshold`, `shift_distance_limit`
- `area_size_limit`, `skip_area`, `fail_if_new`, `fail_on_difference`, `delayed`

The `Diff.configure` block helper provides a convenient way to set both namespaces at once. Since v2, `SnapDiff::Config` (`lib/snap_diff/config.rb`) additionally exposes all 27 settings as one flat object via `SnapDiff.config` / `SnapDiff.configure { |config| ... }` — it holds no state of its own, every accessor forwards to the legacy `mattr_accessor` storage, so both views stay consistent.

## File Layout

```
lib/
  snap_diff.rb                                 # SnapDiff module: compare/start/configure/config
  snap_diff/                                   # Canonical implementation (v2)
    dsl.rb                                     # screenshot(), screenshot_group(), etc.
    config.rb                                  # SnapDiff::Config — flat view over all 27 settings
    deprecation.rb                             # Warn-once-per-constant machinery
    legacy_shims.rb                            # const_missing forwarders for the old namespaces
    comparison.rb                              # Layered comparison engine (ex-ImageCompare)
    comparison_result.rb                       # Comparison result value object (ex-Difference)
    driver.rb                                  # SnapDiff::Driver mixin (ex-BaseDriver superclass)
    drivers.rb                                 # Driver factory
    drivers/
      vips_driver.rb                           # VIPS image processing
      chunky_png_driver.rb                     # ChunkyPNG image processing
    capture/
      viewport.rb                              # Per-capture viewport preparation seam
    screenshoter.rb                            # Basic browser screenshot capture
    stable_screenshoter.rb                     # Stability detection wrapper
    screenshot_matcher.rb                      # Orchestrator for capture + compare
    screenshot_assertion.rb                    # Assertion + registry objects
    screenshot_namer.rb                        # Name/path generation with sections/groups
    snap_manager.rb                            # Screenshot file management
    snap.rb                                    # Single screenshot file abstraction
    reporting.rb                               # Process-global reporter lifecycle
    reporters/
      html.rb                                  # Interactive HTML report reporter
      templates/report.html.erb                # HTML report template
    annotation_service.rb                      # Diff-image annotation (RED_RGBA / ORANGE_RGBA)
    image_preprocessor.rb                      # Pre-processing (skip areas, median filter)
    area_calculator.rb                         # Crop/skip area coordinate resolution
    browser_helpers.rb                         # DOM manipulation helpers
    attempts_reporter.rb                       # Debug reporting for unstable captures
    error_with_filtered_backtrace.rb           # Error with filtered stack
    vcs.rb                                     # Git baseline checkout
    utils.rb                                   # Driver detection
    os.rb                                      # OS detection
    static.rb                                  # Non-Rails static site serving
    version.rb                                 # Gem version
    integrations/
      minitest.rb                              # Minitest assertions integration
      rspec.rb                                 # RSpec matcher integration
      cucumber.rb                              # Cucumber World integration
  capybara_screenshot_diff.rb                  # Umbrella entry point + error classes
  capybara_screenshot_diff/                    # Legacy paths — mostly thin forwarders
    minitest.rb / rspec.rb / cucumber.rb       # Legacy entry points (load the full gem)
    screenshot_assertion.rb                    # CapybaraScreenshotDiff session/reporter shims
    ...                                        # Everything else forwards to snap_diff/
  capybara/screenshot/diff.rb                  # Convenience require (loads minitest)
  capybara/screenshot/diff/
    config_legacy.rb                           # mattr_accessor settings storage (source of truth)
    region.rb                                  # Bounding box region value object (top-level Region)
    version.rb                                 # Capybara::Screenshot::Diff::VERSION (gemspec reads it)
    ...                                        # Everything else forwards to snap_diff/
```

The legacy `Capybara::Screenshot::Diff::*` and `CapybaraScreenshotDiff::*` constants resolve lazily via `snap_diff/legacy_shims.rb` (`const_missing`), pointing at the same objects with a one-time deprecation warning. See [UPGRADING.md](UPGRADING.md) for the migration guide.
