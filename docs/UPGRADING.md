# Upgrading

## Upgrading to v2.0

### Overview

Version 2.0 introduces a new canonical namespace (`SnapDiff`) for cleaner, more discoverable code. The public DSL remains unchanged — your existing `screenshot` and `assert_matches_screenshot` calls work without modification. This guide covers the optional migration path for settings and the new namespace.

**Status:** 2.0 is the **transitional** release — the v1 API and the canonical `SnapDiff` API both work. **2.1 removes** everything 2.0 warns about (the legacy namespaces, the ChunkyPNG driver, `shift_distance_limit`, the `driver:` setting and the driver abstraction). There is no 3.0. Migrating on 2.0 is optional; doing it before 2.1 is not.

**Estimated upgrade time:** 5–15 minutes (most users need only the Gemfile pin)

**Writing new code rather than migrating?** Skip this guide and read
[SnapDiff — the canonical API](snapdiff.md): the same setup, configuration, and extension points
with canonical names only, no legacy shapes to unlearn.

**Breaking changes:** None for the DSL; one migration notice per process plus a deprecation warning per legacy constant you reference (both suppressible), plus the [known caveats](#known-caveats) below

---

### The Short Version (Most Users)

```ruby
# In your Gemfile
gem "capybara-screenshot-diff", "~> 2.0"
```

The same content is also published as `snap_diff-capybara`. Install **one** — with both
in a Gemfile the gem raises `SnapDiff::DualInstallError` at require time.

```bash
bundle install
bundle exec rake test
```

**That's it.** Your existing code works unchanged. The old namespaces (`Capybara::Screenshot::Diff`, `CapybaraScreenshotDiff`) are shimmed with deprecation warnings; the new one (`SnapDiff`) is available if you want to modernize.

---

### What Changed

#### 1. New Canonical Namespace: `SnapDiff`

The implementation now lives in `lib/snap_diff/` under the `SnapDiff` namespace. Every legacy constant still resolves to the *same object*. Most do so lazily and warn once each; a documented set stays eagerly defined and silent — see [Deprecation Warnings](#deprecation-warnings) for exactly which. The main renames:

| Legacy name | v2 canonical name |
|-------------|-------------------|
| `Capybara::Screenshot::Diff::ImageCompare` | `SnapDiff::Comparison` |
| `Capybara::Screenshot::Diff::Difference` | `SnapDiff::ComparisonResult` |
| `Capybara::Screenshot::Diff::Drivers::BaseDriver` | `SnapDiff::Driver` (now a mixin — see below) |
| `CapybaraScreenshotDiff::SnapManager` / `::Snap` | `SnapDiff::SnapManager` / `SnapDiff::Snap` |
| `CapybaraScreenshotDiff::RED_RGBA` / `::ORANGE_RGBA` | `SnapDiff::RED_RGBA` / `SnapDiff::ORANGE_RGBA` |
| `CapybaraScreenshotDiff::Minitest::Assertions` | `SnapDiff::Minitest::Assertions` |
| `require "capybara_screenshot_diff/minitest"` | `require "snap_diff/integrations/minitest"` |
| `require "capybara_screenshot_diff/rspec"` | `require "snap_diff/integrations/rspec"` |
| `require "capybara_screenshot_diff/cucumber"` | `require "snap_diff/integrations/cucumber"` |
| `require "capybara_screenshot_diff/reporters/html"` | `require "snap_diff/reporters/html"` |
| `CapybaraScreenshotDiff.serve` (`…/static`) | `SnapDiff.serve` (`require "snap_diff/static"`) |
| `CapybaraScreenshotDiff.reporters <<` | `SnapDiff::Reporting.register` |
| `CapybaraScreenshotDiff.finalize_reporters!` | `SnapDiff::Reporting.finalize!` |

Note the integration require paths gain an `integrations/` segment — `require "snap_diff/minitest"`
is a `LoadError`.

**What stays the same:**
- `screenshot(name)` — still works
- `assert_matches_screenshot(name)` — still works, still the recommended form
- `capture_screenshot(name)` — still works
- All `compare: false/true` flags and overrides work identically

**What's new (optional):**

```ruby
# Old (still works; constant access now warns once per process)
Capybara::Screenshot::Diff.compare("baseline.png", "current.png")
Capybara::Screenshot::Diff.configure { |screenshot, diff| ... }

# New (recommended for new code)
SnapDiff.compare("baseline.png", "current.png")
SnapDiff.start { |screenshot, diff| ... }         # same shape as old configure
SnapDiff.configure { |config| ... }               # consolidated config object
```

#### 2. Consolidated Configuration: `SnapDiff.config`

Instead of scattering settings across `Capybara::Screenshot` and `Capybara::Screenshot::Diff`, v2.0 offers a single `SnapDiff::Config` object. Both the old and new paths read and write the same underlying storage — writes through either are visible through the other.

**The DSL never changes.** `screenshot` and `assert_matches_screenshot` work exactly as before.

---

### Settings Migration Table

The most commonly-used settings and how to update them:

| Setting | v1.x (still works in v2) | v2.0 (recommended) | What it does |
|---------|----------------------|------------------|------|
| `blur_active_element` | `Capybara::Screenshot.blur_active_element = true` | `SnapDiff.config.blur_active_element = true` | Hide cursor/focus indicator in screenshots (default: `true`) |
| `hide_caret` | `Capybara::Screenshot.hide_caret = true` | `SnapDiff.config.hide_caret = true` | Make input caret transparent for stable comparisons (default: `true`) |
| `tolerance` | `Capybara::Screenshot::Diff.tolerance = 0.0005` | `SnapDiff.config.tolerance = 0.0005` | Pixel-level color difference threshold (higher = less strict) |
| `save_path` | `Capybara::Screenshot.save_path = "doc/screenshots"` | `SnapDiff.config.save_path = "doc/screenshots"` | Where baseline screenshots are stored |
| `window_size` | `Capybara::Screenshot.window_size = [1280, 1024]` | `SnapDiff.config.window_size = [1280, 1024]` | Browser viewport size for consistent screenshots |

**All 27 settings** from both legacy namespaces are available via `SnapDiff.config.<attr_name>` — see the [Configuration Reference](configuration.md) for the full list. One rename to note: `Capybara::Screenshot.enabled` becomes `SnapDiff.config.screenshot_enabled` (it would otherwise collide with `Capybara::Screenshot::Diff.enabled`, which keeps the bare `enabled` name).

---

### Three Ways to Configure

All three are equivalent and use the same underlying storage. Pick the one that fits your style.

#### Option 1: Traditional block (v1 shape, still works)

```ruby
# In test_helper.rb or spec_helper.rb
Capybara::Screenshot::Diff.configure do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
  screenshot.blur_active_element = false
  diff.tolerance = 0.0005
end
```

#### Option 2: SnapDiff block with old shape (backward-compatible)

```ruby
SnapDiff.start do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
  screenshot.blur_active_element = false
  diff.tolerance = 0.0005
end
```

#### Option 3: Consolidated config (cleanest)

```ruby
SnapDiff.configure do |config|
  config.window_size = [1280, 1024]
  config.blur_active_element = false
  config.tolerance = 0.0005
end
```

---

### Prepare Today on v1.x (Zero Risk)

You don't have to wait for v2.0 to start using the new namespace. `SnapDiff.compare` and `SnapDiff.start` were added in v1.14; `SnapDiff.config` / `SnapDiff.configure` in v1.15. All of them work on the current 1.x line:

```ruby
# Works TODAY on v1.15+, zero risk
SnapDiff.compare("baseline.png", "current.png")
SnapDiff.start { |screenshot, diff| ... }
SnapDiff.configure { |config| ... }
```

This means you can migrate your codebase incrementally **now**, before opting into 2.0.

---

### Deprecation Warnings

v2.0 emits three different things, and it is worth knowing which is which. The first two are
about the old namespaces; the third is about the driver features 2.1 removes.

#### 1. The migration notice — one line per process

The first time a process touches *any* hookable legacy API, you get a single line:

```
[snap_diff deprecation] This process uses the v1 `Capybara::Screenshot*` / `CapybaraScreenshotDiff*` API. It still works in 2.0 and is REMOVED in 2.1 -- see docs/UPGRADING.md for the SnapDiff replacements. Silence with `SnapDiff.silence_deprecations = true` or SNAP_DIFF_SILENCE_DEPRECATIONS=1. (shown once per process)
```

It fires once and never again, whichever door you came through:

- a legacy config accessor — `Capybara::Screenshot.window_size = ...`, `Capybara::Screenshot::Diff.tolerance`
- a lazily shimmed legacy constant (see below)
- `include Capybara::Screenshot` / `include Capybara::Screenshot::Diff`

It exists because most of the v1 surface **cannot** warn per use, so without it a 2.x app could
be entirely silent right up to the bare `NameError` it would get on 2.1.

#### 2. Per-constant warnings — one line per lazily shimmed constant

Resolving a legacy constant that is shimmed through `const_missing` also warns, once per constant
per process:

```
[snap_diff deprecation] `Capybara::Screenshot::Diff::ImageCompare` is deprecated (constant); use `SnapDiff::Comparison` instead.
```

**These appear for:** `Capybara::Screenshot::{BrowserHelpers, Screenshoter}`;
`Capybara::Screenshot::Diff::{Vcs, StableScreenshoter, ImagePreprocessor, AreaCalculator,
AnnotationService, Utils, ScreenshotMatcher, Drivers, ImageCompare, Difference}`;
`Capybara::Screenshot::Diff::Drivers::BaseDriver`; `CapybaraScreenshotDiff::{RED_RGBA,
ORANGE_RGBA, SnapManager, Snap, ScreenshotNamer, AttemptsReporter, BacktraceFilter,
ErrorWithFilteredBacktrace, ScreenshotAssertion, AssertionRegistry}`;
`CapybaraScreenshotDiff::Reporters::HTML`.

`CapybaraScreenshotDiff::DSL` and `::Minitest::Assertions` are shimmed this way **only under a
canonical `snap_diff*` require**. Under the v1 entry points — what an unmigrated app actually
uses — they are eagerly defined and silent, like everything in the next section.

#### 3. Removal warnings — the driver half, removed in 2.1

The warnings above are about *names*. These are about *features*: 2.1 makes **libvips the only
image backend** and deletes the rest of the driver machinery. 2.0 still supports all of it and
warns once per process per subject, through the same channel and the same silencing switches.

| You will see it when you… | Removed in 2.1 | Do this instead |
|---|---|---|
| select the ChunkyPNG driver — `driver: :chunky_png`, `SnapDiff.config.driver = :chunky_png`, or the legacy `Capybara::Screenshot::Diff.driver =` | the `:chunky_png` driver | add `gem "ruby-vips"` (plus the libvips system package) and drop the option |
| run on `driver: :auto` **without `ruby-vips` installed** | the `:auto` fallback to ChunkyPNG | same — install libvips + `ruby-vips`. This is the case worth reading twice: nothing in your setup says `chunky_png`, so the warning is the only sign that 2.1 will break this process |
| set `shift_distance_limit` — globally or per screenshot | `shift_distance_limit` (ChunkyPNG-only) | `median_filter_window_size`, `tolerance`, or `color_distance_limit` — see [Configuration](configuration.md#allowed-shift-distance) |
| read `SnapDiff::Drivers.loaded` (the custom-driver registry) | the registry | nothing — custom drivers are removed, see below |
| read `SnapDiff::Drivers.available` | driver detection | require `ruby-vips` instead of branching on a detected list |
| `include SnapDiff::Driver` in your own driver class | the driver mixin | nothing — see below |

> **The one removal on this list that 2.0 cannot warn you about: the `driver:` setting
> itself.** `SnapDiff.config.driver = :vips` (and the legacy
> `Capybara::Screenshot::Diff.driver = :vips`, and the per-screenshot `driver:` override)
> is **silent** in 2.0 and raises `NoMethodError: undefined method 'driver='` in 2.1.
> Warning on it would fire on the recommended configuration, so this note is the warning:
> **delete the line.** With libvips the only backend there is nothing to select, and the
> default just works. The same goes for `driver: :auto` on a machine that *has*
> `ruby-vips` — the `:auto` warning above only fires when `:auto` actually falls back to
> ChunkyPNG, because that is the case where 2.1 stops the process comparing at all.

```
[snap_diff deprecation] `driver: :auto` selected chunky_png because libvips is not available in this process. The chunky_png driver is REMOVED in 2.1, when libvips (the `ruby-vips` gem) becomes required -- install it now, or this setup stops comparing on 2.1. See docs/drivers.md. Silence with `SnapDiff.silence_deprecations = true` or SNAP_DIFF_SILENCE_DEPRECATIONS=1. (shown once per process) (called from /app/test/test_helper.rb:12)
```

**Custom drivers have no migration path.** The whole abstraction goes: the `SnapDiff::Driver`
mixin, the `SnapDiff::Drivers.loaded` registry, `SnapDiff::Drivers.available` /
`SnapDiff::Utils.detect_available_drivers`, and selecting a driver by name. Nothing replaces
them, and this guide is not going to pretend otherwise — if you maintain a third-party driver,
say so on [the issue tracker](https://github.com/snap-diff/snap_diff-capybara/issues) before 2.1 ships.

Three spots on the same chopping block stay silent: the legacy
`Capybara::Screenshot::Diff::LOADED_DRIVERS` / `::AVAILABLE_DRIVERS` aliases are plain constants
with nothing to hook (use `SnapDiff::Drivers.loaded` / `.available` to hear the warning);
`SnapDiff::Drivers.for` is not warned on at all — the gem itself calls it for every comparison,
so warning there would fire on setups that are not affected by anything on this list; and
detection (`SnapDiff::Drivers.detect_available` / `SnapDiff::Utils.detect_available_drivers`)
runs at load, before any user code.

#### Silent by design

Some legacy names never warn individually, and that is deliberate — the migration notice above is
the signal for all of them:

- **Requiring the gem.** `require "capybara_screenshot_diff/minitest"` etc. is not deprecated.
- **The DSL.** `screenshot`, `assert_matches_screenshot`, `capture_screenshot` are never deprecated.
- **Settings access.** `Capybara::Screenshot.blur_active_element`, `Capybara::Screenshot::Diff.tolerance=`
  and the `Diff.configure` block are plain delegators onto `SnapDiff.config`. There is no
  `const_missing` to hook, so they cannot warn per call without adding one on every read.
- **Eagerly defined constants.** `Capybara::Screenshot::Os`, `Capybara::Screenshot::Diff::VERSION`,
  `::Comparison`, `::LOADED_DRIVERS`, `::AVAILABLE_DRIVERS`, `::Reporters::Default`, the top-level
  `Region`, the `CapybaraScreenshotDiff` error classes, and — under the v1 entry points —
  `CapybaraScreenshotDiff::DSL` / `::Minitest::Assertions`. `const_defined?` never triggers
  `const_missing`, so these have to be real constants for adopter feature detection and `rescue`
  clauses to keep working — which means nothing is left to hook.
- **The driver leaf classes.** `Drivers::VipsDriver` / `Drivers::ChunkyPNGDriver` are autoloaded on
  `SnapDiff::Drivers`, so the leaf name itself never warns. Reaching them through the old path still
  warns once for `Capybara::Screenshot::Diff::Drivers` — that part is a `const_missing` shim.
  Each leaf is only declared when its gem is actually installed, so
  `defined?(...Drivers::VipsDriver)` stays `nil` without `ruby-vips`, exactly as in v1.

Every one of those names resolves under a canonical `snap_diff*` require too, so migrating your
`require` line first (as this guide recommends) never breaks a constant you have not renamed yet.

Warnings go through `Kernel#warn`, so test suites that hook `Warning.warn` (e.g. raise-on-warning setups) see them like any other Ruby warning.

#### Silencing Warnings

If warnings appear in a test run and you're not ready to migrate yet:

```ruby
# In test_helper.rb, before running tests
SnapDiff.silence_deprecations = true
```

```bash
# Or as an environment variable
export SNAP_DIFF_SILENCE_DEPRECATIONS=1
```

---

### Known Caveats

Two deliberate consequences of the lazy shim design. Both go away at 2.1, when the shimmed
names go away with them:

1. **`defined?` / `const_defined?` on lazily-shimmed legacy names returns `false`/`nil`.** The shims resolve via `const_missing`, which those checks never trigger. Feature detection like `defined?(Capybara::Screenshot::Diff::ImageCompare)` must move to the `SnapDiff::` name. Everything in [Silent by design](#silent-by-design) is unaffected — those names are real constants, so `defined?`, `const_defined?` and `rescue` all behave as they always did.

2. **Reopening `module Capybara::Screenshot::Diff::Drivers` shadows the shim.** The historical custom-driver monkey-patch pattern defines a fresh, empty `Drivers` module instead of reaching the real one. Define custom drivers under `SnapDiff::Drivers` instead — and note `BaseDriver` is gone as a superclass: `class MyDriver < BaseDriver` becomes `include SnapDiff::Driver` (it's a mixin now).

#### Two moves that fail *silently* if you miss them

**Stubbing the detected-drivers list.** The value moved to `SnapDiff::Drivers::AVAILABLE_DRIVERS`, and `Capybara::Screenshot::Diff::AVAILABLE_DRIVERS` is now an eager alias of it. *Reading* either is identical, but **stubbing the legacy name only rebinds the alias** — the gem keeps reading the canonical constant, so a test that stubs it to `[]` no longer exercises the no-drivers path and just passes for the wrong reason:

```ruby
# before
Capybara::Screenshot::Diff.stub_const(:AVAILABLE_DRIVERS, []) { ... }
# now
SnapDiff::Drivers.stub_const(:AVAILABLE_DRIVERS, []) { ... }
```

**`SnapDiff::Config::MAPPING` is gone.** It split in two: `SnapDiff::Config::SETTINGS` (the setting names, no legacy knowledge) and `SnapDiff::LegacyShims::CONFIG_MAPPING` (which legacy holder each name hangs off). If you referenced `MAPPING` — iterating settings in a test helper, say — use `SETTINGS`; `CONFIG_MAPPING` is `@api private` and disappears in 2.1 with the rest of the v1 surface.

---

### FAQ

#### "My tests pass but I see warnings. Should I worry?"

No. Warnings are informational and fully suppressible. They're designed to catch legacy namespace references, not break existing CI. If silence is preferable for now, set `SNAP_DIFF_SILENCE_DEPRECATIONS=1` and migrate at your pace.

#### "Does the DSL change at all?"

No. `screenshot`, `assert_matches_screenshot`, and `capture_screenshot` are stable and unchanged. All overrides (`:compare`, `:tolerance`, etc.) work identically.

#### "Can I mix old and new config in the same suite?"

Yes. Both paths write to the same underlying storage:

```ruby
Capybara::Screenshot::Diff.configure do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
end

SnapDiff.configure do |config|
  config.tolerance = 0.0005  # Same storage, visible to the old path too
end
```

#### "What if I need to roll back?"

All settings and baselines are compatible with v1.x. Simply pin your Gemfile back to `"~> 1.15"` and `bundle update capybara-screenshot-diff`.

---

### Summary Checklist

- [ ] Pin `gem "capybara-screenshot-diff", "~> 2.0"` in your Gemfile
- [ ] Run `bundle install`
- [ ] Run your test suite to verify no regressions
- [ ] Read the warnings it prints — each one names something 2.1 removes
- [ ] Add `gem "ruby-vips"` if you are not already on it (2.1 makes libvips the only backend)
- [ ] Drop `driver:` from your config — it is silent in 2.0 and gone in 2.1
- [ ] (Optional, but do it before 2.1) Migrate config and constants to the `SnapDiff` namespace
- [ ] (Optional) Silence deprecation warnings if not ready to migrate
- [ ] Report anything surprising on [the issue tracker](https://github.com/snap-diff/snap_diff-capybara/issues)

---

## Upgrading to v1.13.0

### Overview

Version 1.13.0 is a **minor release** clarifying API terminology and adding new capture methods. No breaking changes — your existing code continues to work.

**Estimated upgrade time:** 0 minutes (no action required for most users)

---

### Quick Upgrade Path (Most Users)

```ruby
# In your Gemfile
gem 'capybara-screenshot-diff', '~> 1.13.0'
```

```bash
bundle update capybara-screenshot-diff
bundle exec rake test
```

**That's it!** Existing `screenshot` calls work unchanged. New methods available if needed.

---

### What Changed

#### API Clarification: Primary Method is `assert_matches_screenshot`

**v1.12.0 and earlier:** `screenshot` was the primary method  
**v1.13.0+:** `assert_matches_screenshot` is the primary method

**Action required:** None. `screenshot` continues to work as-is.

The method names now better reflect their behavior:
- `assert_matches_screenshot(name)` — takes screenshot and asserts it matches baseline
- `screenshot(name, compare: true)` — convenience wrapper (same behavior as above when `compare: true`)
- `capture_screenshot(name)` — new: captures without asserting

```ruby
# All three work and are safe to use:
assert_matches_screenshot "homepage"                # Primary: explicit intent
screenshot "homepage"                               # Shorthand (familiar)
screenshot "homepage", compare: false               # Capture only
capture_screenshot "homepage"                       # Also capture only
```

**Safe to override:** You can safely define your own `screenshot` method in your test base class — the gem's implementation won't interfere.

---

### New: `capture_screenshot` Method

Capture without comparing to baseline:

```ruby
capture_screenshot "dynamic_page"  # No assertion
```

Equivalent to: `screenshot "dynamic_page", compare: false`

---

### New: `Diff.pending_if_new` Helper

Mark baseline-less tests pending instead of failing during initial CI runs:

```ruby
# In test_helper.rb — before running tests
Capybara::Screenshot::Diff.pending_if_new = true
```

**CI requirement:** When using `pending_if_new`, ensure CI is configured with `fail_if_new: false` (see [Configuration Reference](configuration.md#quick-setup)):

```ruby
Capybara::Screenshot::Diff.configure do |screenshot, diff|
  diff.fail_if_new = false  # Allow baselines to be added
end
```

---

## Upgrading to v1.12.0

### Overview

Version 1.12.0 is a **minor release** with new features, performance improvements, and default behavior changes. This guide will help you upgrade smoothly.

**Estimated upgrade time:** 5-15 minutes depending on your setup

---

## Quick Upgrade Path (Most Users)

For **most users**, upgrading is as simple as:

```ruby
# In your Gemfile
gem 'capybara-screenshot-diff', '~> 1.12.0'
```

```bash
bundle update capybara-screenshot-diff
bundle exec rake test  # Verify tests still pass
```

**That's it!** The zero-config setup still works out of the box. Your existing screenshot comparisons will continue to work with v1.12.0.

---

## Breaking Changes & Migration Steps

### 1. Default Behavior Changes (Most Important)

Three settings now have different defaults. This is the most likely source of unexpected test failures.

#### `blur_active_element` — Now defaults to `true`

**Before (v1.11.x):** Cursor blinking could delay screenshots  
**After (v1.12.0):** Cursor is automatically hidden

**Action required:** Only if you want the old behavior

```ruby
# To restore v1.x behavior:
Capybara::Screenshot.blur_active_element = false
```

#### `hide_caret` — Now defaults to `true`

**Before (v1.11.x):** Input caret visible in screenshots  
**After (v1.12.0):** Caret is transparent for stable screenshots

**Action required:** Only if you want the old behavior

```ruby
# To restore v1.x behavior:
Capybara::Screenshot.hide_caret = false
```

#### `fail_if_new` — Now defaults to `true` in CI

**Before (v1.11.x):** New screenshots allowed in CI  
**After (v1.12.0):** New screenshots fail tests in CI (when `ENV['CI']` is set)

**Action required:** Only if you want to allow new screenshots in CI

```ruby
# To allow new screenshots in CI:
Capybara::Screenshot::Diff.fail_if_new = false
```

**Why this changed:** This prevents accidental baseline additions in CI pipelines. Most teams want this behavior.

---

### 2. SVN Support Removed

**Before (v1.11.x):** Could use SVN for version control  
**After (v1.12.0):** Git only

**Action required:** If using SVN, migrate to Git

```bash
# Check if you're using SVN for screenshots
git grep svn test/  # Look for svn commands in your tests
```

If you find SVN usage:
1. Export your SVN repository to Git
2. Update your CI/CD to use Git
3. Re-commit all screenshot baselines with Git

**Why this changed:** SVN support was rarely used and added maintenance burden.

---

### 3. ActiveSupport No Longer Required

**Before (v1.11.x):** ActiveSupport was a runtime dependency  
**After (v1.12.0):** Pure Ruby, no ActiveSupport required

**Action required:** None (this is a positive change!)

If your project only had ActiveSupport because of this gem, you can now remove it:

```ruby
# In your Gemfile — can likely be removed if only used for this gem
# gem 'activesupport'  # ← Remove if not used elsewhere
```

**Why this changed:** Lighter installations, faster boot times.

---

### 4. Internal API Changes

**Before (v1.11.x):** Could use internal classes like `CaptureStrategy`, `ComparisonLoader`  
**After (v1.12.0):** These have been inlined/refactored

**Action required:** Only if using internal APIs

Check your codebase:

```bash
# Search for internal API usage
grep -r "CaptureStrategy" test/ lib/
grep -r "ComparisonLoader" test/ lib/
grep -r "ScreenshotCoordinator" test/ lib/
grep -r "ImagePreprocessor" test/ lib/
```

If you find usage, these were never part of the public API and should be replaced with the documented public API.

**Why this changed:** Simplified architecture, better performance, easier maintenance.

---

## New Features to Try

### HTML Reporter (Recommended)

Get an interactive dashboard showing all screenshot differences:

```ruby
# Add to test_helper.rb or spec_helper.rb
require 'capybara_screenshot_diff/reporters/html'
```

After running tests:

```bash
open doc/screenshots/snap_diff_report.html
```

**Features:**
- Side-by-side comparison with diff toggle
- Thumbnail sidebar for navigation
- Search functionality
- Summary statistics

---

### Standalone Image Comparison

Compare any two images without Capybara or a browser:

```ruby
result = Capybara::Screenshot::Diff.compare("baseline.png", "current.png")
result.quick_equal?  # => true if byte-identical
result.different?    # => true if visually different
```

**Use cases:**
- PDF regression testing
- Generated image validation
- CI artifact verification

---

### Perceptual Color Distance (Anti-aliasing Fix)

Eliminate false positives from font rendering differences:

```ruby
# Global configuration
Capybara::Screenshot::Diff.perceptual_threshold = 2.0

# Or per-screenshot
screenshot 'dashboard', perceptual_threshold: 2.0
```

**dE00 Scale Reference:**
- `< 1.0` — Not perceptible by human eyes
- `1-2` — Perceptible through close observation (anti-aliasing, font hinting)
- `2-10` — Perceptible at a glance (color shifts, layout changes)
- `> 10` — Clearly different colors

**Why use this:** If you see false positives from font rendering differences across CI environments.

---

### `assert_no_screenshot_changes`

Assert that an action produces no visual change:

```ruby
test "clicking cancel doesn't change page" do
  visit '/edit'
  screenshot 'before_cancel'
  
  click_button 'Cancel'
  
  assert_no_screenshot_changes 'after_cancel'
end
```

---

### Simplified Configuration

Use the new `Diff.configure` block:

```ruby
# In test_helper.rb — one line, that's it
Capybara::Screenshot::Diff.configure do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
  screenshot.stability_time_limit = 1
  diff.driver = :vips
  diff.tolerance = 0.0005
end
```

---

## Performance Improvements

Enjoy faster screenshot comparisons:

- **ChunkyPNG:** Eliminated array allocations in shift-detection (~30% faster for large images)
- **VIPS:** Cached computations at construction (~15% faster)
- **General:** Memoized region area size, replaced closures with blocks

**No action required** — these are automatic improvements.

---

## Ruby & Rails Compatibility

### Supported Versions

- **Ruby:** 3.2, 3.3, 3.4, 3.5 (new!), 4.0 (new!)
- **Rails:** 7.1, 7.2, 8.0

### Upgrade Notes

**Ruby 4.0:** Fully compatible! If you see DSLStub ordering issues, they're fixed in v1.12.0.

**Rails 8.0:** Works out of the box with updated dependencies.

---

## Testing Your Upgrade

### Step 1: Update Gemfile

```ruby
gem 'capybara-screenshot-diff', '~> 1.12.0'
```

### Step 2: Bundle Update

```bash
bundle update capybara-screenshot-diff
```

### Step 3: Run Tests

```bash
bundle exec rake test
```

### Step 4: Check for New Screenshot Failures

If tests fail with new screenshot errors in CI:

1. **Option A:** Commit the new baselines (recommended if changes are intentional)
2. **Option B:** Set `fail_if_new = false` temporarily (not recommended long-term)

### Step 5: Enable HTML Reporter (Optional)

```ruby
require 'capybara_screenshot_diff/reporters/html'
```

Run tests and open `doc/screenshots/snap_diff_report.html` to review differences.

---

## Troubleshooting

### "Tests fail with new screenshots in CI"

**Cause:** `fail_if_new` now defaults to `true` in CI

**Solution:**

```bash
# Commit the new baselines
git add doc/screenshots/
git commit -m "Add screenshot baselines for v1.12.0 upgrade"
```

Or temporarily allow them:

```ruby
Capybara::Screenshot::Diff.fail_if_new = false
```

### "Screenshots look different after upgrade"

**Cause:** `blur_active_element` and `hide_caret` now default to `true`

**Solution:** Restore v1.x behavior temporarily:

```ruby
Capybara::Screenshot.blur_active_element = false
Capybara::Screenshot.hide_caret = false
```

Then re-record baselines with the new defaults (recommended):

```bash
# Delete old baselines
rm doc/screenshots/*.png

# Run tests to generate new baselines
bundle exec rake test

# Commit new baselines
git add doc/screenshots/
git commit -m "Re-record baselines with v1.12.0 defaults"
```

### "NoMethodError on internal class"

**Cause:** Using internal APIs that were refactored

**Solution:** Use the public API instead. Check the documentation for the correct interface.

---

## Rollback Plan

If you need to rollback:

```ruby
# Pin to previous version
gem 'capybara-screenshot-diff', '~> 1.12.0'
```

```bash
bundle update capybara-screenshot-diff
```

All screenshot baselines are compatible — no data loss.

---

## Need Help?

- **Documentation:** [README.md](../README.md)
- **Changelog:** [CHANGELOG.md](CHANGELOG.md)
- **Issues:** [GitHub Issues](https://github.com/snap-diff/snap_diff-capybara/issues)
- **DeepWiki:** [Code Documentation](https://deepwiki.com/snap-diff/snap_diff-capybara)

---

## Summary Checklist

- [ ] Update gem version to `~> 1.12.0`
- [ ] Run `bundle update capybara-screenshot-diff`
- [ ] Run test suite
- [ ] Check for new screenshot failures in CI
- [ ] Decide on `fail_if_new` behavior
- [ ] Decide on `blur_active_element` and `hide_caret` defaults
- [ ] Enable HTML reporter (optional)
- [ ] Re-record baselines if needed
- [ ] Commit changes
- [ ] Review upgrade issues in [GitHub Issues](https://github.com/snap-diff/snap_diff-capybara/issues)

**Congratulations!** You're now running v1.12.0 🎉
