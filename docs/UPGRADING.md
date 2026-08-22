# Upgrading

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

- **Documentation:** [README.md](README.md)
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
