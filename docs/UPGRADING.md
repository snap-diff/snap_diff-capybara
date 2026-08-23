# Upgrading

## Upgrading to v2.0 (alpha)

### Overview

Version 2.0 introduces a new canonical namespace (`SnapDiff`) for cleaner, more discoverable code. The public DSL remains unchanged — your existing `screenshot` and `assert_matches_screenshot` calls work without modification. This guide covers the optional migration path for settings and the new namespace.

**Status:** `2.0.0.beta3` is an opt-in prerelease. RubyGems never installs prereleases by default resolution — normal `bundle update` keeps you on the 1.x line. The final 2.0.0 ships only after adopter feedback; please report anything surprising on [#166](https://github.com/snap-diff/snap_diff-capybara/issues/166).

**Estimated upgrade time:** 5–15 minutes (most users need only the Gemfile pin)

**Writing new code rather than migrating?** Skip this guide and read
[SnapDiff — the canonical API](snapdiff.md): the same setup, configuration, and extension points
with canonical names only, no legacy shapes to unlearn.

**Breaking changes:** None for the DSL; deprecation warnings if you reference legacy constants (suppressible), plus two known alpha caveats (see below)

---

### The Short Version (Most Users)

```ruby
# In your Gemfile — the exact prerelease version is required to opt in
gem "capybara-screenshot-diff", "2.0.0.beta3" # or the latest 2.0.0 prerelease
```

```bash
bundle install
bundle exec rake test
```

**That's it.** Your existing code works unchanged. The old namespaces (`Capybara::Screenshot::Diff`, `CapybaraScreenshotDiff`) are shimmed with deprecation warnings; the new one (`SnapDiff`) is available if you want to modernize.

---

### What Changed

#### 1. New Canonical Namespace: `SnapDiff`

The implementation now lives in `lib/snap_diff/` under the `SnapDiff` namespace. Every legacy constant still resolves — lazily, to the *same object* — but emits a one-time-per-constant deprecation warning. The main renames:

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
  diff.driver = :vips
end
```

#### Option 2: SnapDiff block with old shape (backward-compatible)

```ruby
SnapDiff.start do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
  screenshot.blur_active_element = false
  diff.tolerance = 0.0005
  diff.driver = :vips
end
```

#### Option 3: Consolidated config (cleanest)

```ruby
SnapDiff.configure do |config|
  config.window_size = [1280, 1024]
  config.blur_active_element = false
  config.tolerance = 0.0005
  config.driver = :vips
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

In v2.0, resolving a legacy *constant* emits one deprecation warning per constant per process:

```
[snap_diff deprecation] `Capybara::Screenshot::Diff::ImageCompare` is deprecated (constant); use `SnapDiff::Comparison` instead.
```

**Warnings appear for:** legacy constant access — `Capybara::Screenshot::Diff::ImageCompare`, `::Difference`, `::Drivers`, `CapybaraScreenshotDiff::SnapManager`, etc.

**Warnings do NOT appear for:**
- Requiring the gem: `require "capybara_screenshot_diff/minitest"` etc. is not deprecated
- The DSL: `screenshot`, `assert_matches_screenshot`, `capture_screenshot` are never deprecated
- Settings access: `Capybara::Screenshot.blur_active_element`, `Capybara::Screenshot::Diff.tolerance=`, and the `Diff.configure` block stay silent — they remain the canonical storage that `SnapDiff.config` forwards to
- A few advertised entry-point constants that stay eagerly defined by design: `Capybara::Screenshot::Os`, `CapybaraScreenshotDiff::DSL`, `Capybara::Screenshot::Diff::VERSION`, and the driver leaf classes (`Drivers::VipsDriver`, `Drivers::ChunkyPNGDriver`)

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

### Known Alpha Caveats

Two deliberate consequences of the lazy shim design — both flagged for feedback on [#166](https://github.com/snap-diff/snap_diff-capybara/issues/166):

1. **`defined?` / `const_defined?` on lazily-shimmed legacy names returns `false`/`nil`.** The shims resolve via `const_missing`, which those checks never trigger. Feature detection like `defined?(Capybara::Screenshot::Diff::ImageCompare)` must move to the `SnapDiff::` name. Rescuing legacy *error classes* is unaffected — they remain eagerly defined.

2. **Reopening `module Capybara::Screenshot::Diff::Drivers` shadows the shim.** The historical custom-driver monkey-patch pattern defines a fresh, empty `Drivers` module instead of reaching the real one. Define custom drivers under `SnapDiff::Drivers` instead — and note `BaseDriver` is gone as a superclass: `class MyDriver < BaseDriver` becomes `include SnapDiff::Driver` (it's a mixin now).

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

- [ ] Pin `gem "capybara-screenshot-diff", "2.0.0.beta3"` (or the latest 2.0.0 prerelease) in your Gemfile
- [ ] Run `bundle install`
- [ ] Run your test suite to verify no regressions
- [ ] (Optional) Migrate config to the `SnapDiff` namespace
- [ ] (Optional) Silence deprecation warnings if not ready to migrate
- [ ] Report anything surprising on [#166](https://github.com/snap-diff/snap_diff-capybara/issues/166)

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
