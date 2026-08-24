# Configuration Reference

## Quick Setup

**Canonical (v2):** every setting lives on one flat object, `SnapDiff.config`.

```ruby
# In test_helper.rb or rails_helper.rb
SnapDiff.configure do |config|
  config.window_size = [1280, 1024]
  config.stability_time_limit = 1
  config.blur_active_element = true
  config.hide_caret = true
  config.tolerance = 0.0005
  config.color_distance_limit = 15
end
```

**Legacy (still supported):** the two-holder block, split across `Capybara::Screenshot` and
`Capybara::Screenshot::Diff`.

```ruby
Capybara::Screenshot::Diff.configure do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
  screenshot.stability_time_limit = 1
  screenshot.blur_active_element = true
  screenshot.hide_caret = true
  diff.tolerance = 0.0005
  diff.color_distance_limit = 15
end
```

> **`driver:` is deliberately absent from both examples.** The setting is removed in 2.1
> (`NoMethodError` at config time) and 2.0 cannot warn about it. Add `gem "ruby-vips"` and
> leave the selection alone — see [Drivers](drivers.md#removed-in-21-everything-on-this-page-except-vips).

`SnapDiff::Config` **is** the storage; the legacy accessors are thin delegators onto it. There is
one source of truth, so a write through either surface is visible through the other — mixing them
is safe, and you can migrate a suite one line at a time:

```ruby
SnapDiff.config.window_size = [1280, 1024]
Capybara::Screenshot.window_size    # => [1280, 1024]
```

Every option name below is identical on both surfaces — only the receiver changes. The one
exception: `Capybara::Screenshot.enabled` is `SnapDiff.config.screenshot_enabled`, because
`SnapDiff.config.enabled` is taken by `Capybara::Screenshot::Diff.enabled`. See
[SnapDiff — the canonical API](snapdiff.md) for the full SnapDiff-native surface.

**Note:** Setting `Capybara::Screenshot.enabled = false` is sufficient to disable all screenshots. There is no need to define no-op modules or monkey-patch the gem.

## Record modes — accepting changes

`record` is the single setting for *what happens when a screenshot has no committed baseline, or
when you want to accept the ones that changed*. It replaces `fail_if_new`, which is removed in 2.1.

```ruby
SnapDiff.config.record = :once   # what a local run already does; see Precedence below for CI
```

| Mode | Missing baseline | Baseline present | Reach for it when |
|------|------------------|------------------|-------------------|
| `:once` | recorded, not compared | compared | the default — you want a normal run |
| `:none` | **fails** with the `git add` command attached | compared | every screenshot must already be recorded |
| `:all` | recorded | **re-recorded, not compared** | you changed the UI on purpose and want the new rendering to become the baseline |

### `:all` — the bulk-accept verb

After an intentional redesign that changed forty screenshots, re-record them in one run rather
than accepting them one failure at a time:

```ruby
# test_helper.rb. There is no CLI flag — the gem has no runner to hang one on —
# so gate it on an environment variable of your own if you want one:
SnapDiff.config.record = ENV["ACCEPT_SCREENSHOTS"] ? :all : :once
```

```bash
ACCEPT_SCREENSHOTS=1 bin/rails test:system     # with the line above in test_helper.rb
```

Every screenshot is written to its baseline path and nothing is compared, so `git status` lists
exactly what changed. Review the images, then commit them — see
[Accepting an intentional change](../README.md#accepting-an-intentional-change).

At the end of the run the gem names what it accepted:

```
[snap_diff] record: :all re-recorded 3 screenshots WITHOUT comparing: checkout/cart, checkout/payment, checkout/review. Review the result before committing -- an unintended change is accepted just as silently.
```

> **`:all` refuses to run under CI** (when `ENV['CI']` is set to a non-empty value). It accepts
> every rendering by design, so a mode left in a committed config file would buy you a build that
> compares nothing and passes forever, with the "recorded" screenshots discarded when the runner
> is torn down. Re-record locally, where you can look at the result.
>
> A CI job that needs to record screenshots with **no baseline yet** does not need `:all`:
> `record = :once` records those and still compares everything that has a baseline. See
> [CI integration](ci-integration.md).

### Per screenshot

```ruby
assert_matches_screenshot "flaky_widget", record: :none   # this one must already exist
```

### Precedence

**An explicitly set mode outranks `fail_if_new`; `fail_if_new` decides only when no mode was set.**
That is the same rule `fail_if_new` itself has over the `CI` sniff — explicit outranks implicit, all
the way down. Per screenshot outranks the config; the config outranks `fail_if_new`.

With **nothing** set, `record` reads back as `:none` under CI and `:once` off it — which is exactly
what `fail_if_new` has always done, so a suite that never mentions `record` behaves as it always
did. The missing-baseline default is deliberately unchanged: failing only under CI is what Jest,
AVA, Vitest, testthat and jest-image-snapshot all chose, and a screenshot baseline recorded on your
laptop is often worthless on another OS. `:none` makes strictness an explicit choice instead.

| You wrote | `record` reads | Missing baseline |
|-----------|----------------|------------------|
| nothing, off CI | `:once` | recorded |
| nothing, under CI | `:none` | fails |
| `record = :once` | `:once` | recorded, on CI too |
| `record = :none` | `:none` | fails, off CI too |
| `record = :once`, `fail_if_new = true` | `:once` | recorded — the mode wins |
| `record = nil`, `fail_if_new = true` | `:none` | fails — nil hands it back |

A misspelt mode raises `ArgumentError` at the point you set it, rather than reading back as
"nobody said".

## Recommended tolerance values

| Use Case | VIPS `tolerance` | ChunkyPNG `color_distance_limit` | `stability_time_limit` |
|----------|-----------------|--------------------------------|----------------------|
| Animated/complex pages | 0.01 | 30 | 2s |
| Standard Rails apps | 0.001 (default) | 15 | 1s |
| Pixel-perfect design tests | 0.0001 | 5 | 1s |

**Note:** VIPS defaults to `tolerance: 0.001` (allows 0.1% pixel difference). ChunkyPNG has no default tolerance.

## Choosing the Right Color Comparison Method

**Important:** `perceptual_threshold`, `color_distance_limit`, and `tolerance` serve different purposes. Use this decision tree:

### Step 1: Choose color comparison method (pick ONE)

| Method | Scale | Driver | Best for |
|--------|-------|--------|----------|
| `perceptual_threshold` | 0-100+ (dE00) | VIPS only | Cross-OS/browser font rendering, anti-aliasing |
| `color_distance_limit` | 0-510 (RGBA Euclidean) | VIPS, ChunkyPNG | Legacy setups, fine-grained RGB control |

**Recommendation:** Use `perceptual_threshold: 2.0` for most cases. It matches human perception and needs less tuning.

**⚠️ Color comparison methods are exclusive:** `perceptual_threshold` and `color_distance_limit` cannot both be active — if you set both, `perceptual_threshold` wins and `color_distance_limit` is ignored. However, `tolerance` works with **both** methods and is applied by default for VIPS (0.001). This means even with `perceptual_threshold: 2.0`, the `tolerance: 0.001` default still filters results.

### Step 2: Set tolerance (optional, independent)

| Setting | What it does | Scale |
|---------|--------------|-------|
| `tolerance` | Maximum allowed *ratio* of different pixels (VIPS) or diff bounding box (ChunkyPNG) | 0.0-1.0 |

**Example:** `tolerance: 0.001` allows 0.1% of the image to differ (e.g., 125 pixels in a 1280×1024 screenshot).

**Key difference:**
- `perceptual_threshold` / `color_distance_limit` → **"how different can a pixel be?"**
- `tolerance` → **"how many pixels can differ?"**

**⚠️ Driver difference:** VIPS counts actual different pixels. ChunkyPNG counts the bounding box area around differences — a single pixel diff creates a box, and the entire box area counts against tolerance. This makes ChunkyPNG stricter with the same tolerance value.

### Quick start

```ruby
# Modern approach (recommended)
screenshot 'dashboard', perceptual_threshold: 2.0

# Allow small noise regions
screenshot 'dashboard', perceptual_threshold: 2.0, tolerance: 0.001

# Legacy ChunkyPNG setup
screenshot 'dashboard', color_distance_limit: 15
```

## Configuration Tiers

**Tier 1 — Zero config (works immediately):**
`blur_active_element` and `hide_caret` are on by default, and `record` behaves as `:none` in CI
(a missing baseline fails) and `:once` off it.
Just `require 'snap_diff/integrations/minitest'` (legacy: `capybara_screenshot_diff/minitest`) and call `screenshot`.

**Tier 2 — Set when tests are flaky:**

| Setting | When to use |
|---------|-------------|
| `window_size` | Screenshots differ between machines due to different browser sizes |
| `tolerance` | Sub-pixel rendering differences cause false positives |
| `skip_area` | Dynamic content (timestamps, ads) changes between runs |
| `stability_time_limit` | Animations or loading states cause inconsistent captures |

**Tier 3 — Advanced tuning:**

| Setting | When to use |
|---------|-------------|
| `perceptual_threshold` | Anti-aliasing false positives across OS/browser versions |
| `shift_distance_limit` | Content shifts by a few pixels (ChunkyPNG only — **removed in 2.1**) |
| `area_size_limit` | Allow small diff regions below a pixel count |
| `color_distance_limit` | Fine-tune raw RGB channel tolerance |
| `median_filter_window_size` | Smooth noise before comparison (VIPS only) |

---

## Common Options

### Screen size

You can specify the desired screen size using

```ruby
Capybara::Screenshot.window_size = [1024, 768]
```

This will force the screen shots to the given size, and skip taking screen shots
unless the desired window size can be achieved.

### Disabling screen shots

If you want to skip taking screen shots, set

```ruby
Capybara::Screenshot.enabled = false
```

You can of course set this by an environment variable

```ruby
Capybara::Screenshot.enabled = ENV['TAKE_SCREENSHOTS']
```

### Disabling diff

If you want to skip the assertion for change in the screen shot, set

```ruby
Capybara::Screenshot::Diff.enabled = false
```

Using an environment variable

```ruby
Capybara::Screenshot::Diff.enabled = ENV['COMPARE_SCREENSHOTS']
```

### Tolerate screenshot differences

> **Removed in 2.1.** A screenshot that differs from its baseline fails — that is what the gem is
> for. To *accept* a difference, re-record it: [`record = :all`](#record-modes--accepting-changes).
> It keeps working for the whole 2.x line and warns once per process.

To allow screenshot differences, but still fail on functional errors, you can set the following option:

```ruby
Capybara::Screenshot::Diff.fail_on_difference = false
```

It defaults to `true`.  This can be useful in continuous integration to a generate a screenshot difference
report while still reporting functional errors.

### Does not tolerate new screenshots

> **Removed in 2.1, superseded by [`record`](#record-modes--accepting-changes).**
> `record = :none` is `fail_if_new = true`; `record = :once` is `fail_if_new = false`. Unlike the
> boolean, a mode means the same thing on CI and off it. It keeps working for the whole 2.x line and
> warns once per process.

To fail the test if a new screenshot is taken, set the following option:

```ruby
Capybara::Screenshot::Diff.fail_if_new = true
```

If `fail_if_new` is set to `true`, the test will fail if a new screenshot is taken
that does not have a corresponding previous image to compare against.
This can be useful in situations where you want to ensure
that every screenshot taken by your tests corresponds to an expected state of your application.

`fail_if_new` defaults to `true` in CI environments (when `ENV['CI']` is set to a non-empty value).
Setting it yourself outranks the environment: `fail_if_new = false` stays `false` under `CI=true`.
Assign `nil` to hand it back to the environment. Setting `record` outranks it either way.

### Marks new screenshots as pending

> **Removed in 2.1.** It skips the test instead of saying what to do about the missing baseline.
> [`record = :none`](#record-modes--accepting-changes) fails with the `git add` command attached;
> `record = :once` records the screenshot and names it in the end-of-run summary. It keeps working
> for the whole 2.x line and warns once per process.

To mark tests as pending (skipped) if a new screenshot is taken without a baseline, set:

```ruby
Capybara::Screenshot::Diff.pending_if_new = true
# Required in CI, because fail_if_new defaults to true there and raises before
# the pending marker is applied.
Capybara::Screenshot::Diff.fail_if_new = false
```

If `pending_if_new` is set to `true`, the test will be marked as skipped in teardown
when a new screenshot has no committed baseline to compare against.
This is complementary to `fail_if_new` (which raises immediately); `fail_if_new` takes precedence since it raises first.
This option is useful when you want to record new screenshots without blocking CI, but still track them as needing review.

### Screen shot save path

By default, `Capybara::Screenshot::Diff` saves screenshots to a
`doc/screenshots` folder, relative to either `Rails.root` (if you're in Rails),
or your current directory otherwise.

If you want to change where screenshots are saved to, then there are two
configuration options that that are relevant.

The most likely one you'll want to modify is ...

```ruby
Capybara::Screenshot.save_path = "other/path"
```

The `save_path` option is relative to `Capybara::Screenshot.root`.

`Capybara::Screenshot.root` defaults to either `Rails.root` (if you're in
Rails) or your current directory. You can change it to something entirely
different if necessary, such as when using an alternative web framework.

```ruby
Capybara::Screenshot.root = Hanami.root
```

### Screen shot stability

To ensure that animations are finished before saving a screen shot, you can add
a stability time limit.  If the stability time limit is set, a second screen
shot will be taken and compared to the first.  This is repeated until two
subsequent screen shots are identical.

```ruby
Capybara::Screenshot.stability_time_limit = 0.1
```

This can be overridden on a single screenshot:

```ruby
test 'stability_time_limit' do
  visit '/'
  screenshot 'index', stability_time_limit: 0.5
end
```

### Maximum wait limit

When the `stability_time_limit` is set, but no stable screenshot can be taken, a timeout occurs.
The timeout occurs after `Capybara.default_max_wait_time`, but can be overridden by an option.

```ruby
test 'max wait time' do
  visit '/'
  screenshot 'index', wait: 20.seconds
end
```

### Hiding the caret for active input elements

In Chrome the screenshot includes the blinking input cursor.  This can make it impossible to get a
stable screenshot.  To get around this you can set the `hide caret` option:

```ruby
Capybara::Screenshot.hide_caret = true
```

This will make the cursor (caret) transparent (invisible), so the blinking does not delay the screen shot.


### Removing focus from the active element

Another way to avoid the cursor blinking is to set the `blur_active_element` option:

```ruby
Capybara::Screenshot.blur_active_element = true
```

This will remove the focus from the active element, removing the blinking cursor.



### Allowed color distance

Sometimes you want to allow small differences in the images.  For example, Chrome renders the same
page slightly differently sometimes.  You can set set the color difference threshold for the
comparison using the `color_distance_limit` option to the `screenshot` method:

```ruby
test 'color threshold' do
  visit '/'
  screenshot 'index', color_distance_limit: 30
end
```

The difference is calculated as the euclidean distance.  You can also set this globally:

```ruby
Capybara::Screenshot::Diff.color_distance_limit = 42
```


### Allowed shift distance

> **Removed in 2.1.** `shift_distance_limit` is implemented only by the ChunkyPNG driver,
> and 2.1 removes that driver — libvips becomes the only backend. Setting it anywhere
> (`SnapDiff.config.shift_distance_limit =`, the legacy
> `Capybara::Screenshot::Diff.shift_distance_limit =`, or `screenshot 'index',
> shift_distance_limit: 2`) warns once per process in 2.0. There is no vips equivalent:
> use `median_filter_window_size` (the faster answer to the same problem — see
> [Drivers](drivers.md#median-filter-size-vips-only)), `tolerance`, or
> `color_distance_limit`.

Sometimes you want to allow small movements in the images.  For example, jquery-tablesorter
renders the same table slightly differently sometimes.  You can set set the shift distance
threshold for the comparison using the `shift_distance_limit` option to the `screenshot`
method:

```ruby
test 'color threshold' do
  visit '/'
  screenshot 'index', shift_distance_limit: 2
end
```

The difference is calculated as maximum distance in either the X or the Y axis.
You can also set this globally:

```ruby
Capybara::Screenshot::Diff.shift_distance_limit = 1
```

**Note:** For each increase in `shift_distance_limit` more pixels are searched for a matching color value, and
this will impact performance **severely** if a match cannot be found.

If `shift_distance_limit` is `nil` shift distance is not measured.  If `shift_distance_limit` is set,
even to `0`, shift distance is measured and reported on image differences.

### Allowed difference size

You can set set a threshold for the differing area size for the comparison
using the `area_size_limit` option to the `screenshot` method:

```ruby
test 'area threshold' do
  visit '/'
  screenshot 'index', area_size_limit: 17
end
```

The difference is calculated as `width * height`.  You can also set this globally:

```ruby
Capybara::Screenshot::Diff.area_size_limit = 42
```


### Skipping an area

Sometimes you have expected change that you want to ignore.
You can use the `skip_area` option with `[left, top, right, bottom]`
or css selector like `'#footer'` or `'.container .skipped_element'` to the `screenshot` method to ignore an area.
Be aware that if the selector is not in the page then the library will wait the default wait time for it to appear.
Therefore, it is best to only use css selectors for skip_areas you know will be in the page:

```ruby
test 'unstable area' do
  visit '/'
  screenshot 'index', skip_area: [[17, 6, 27, 16], '.container .skipped_element', '#footer']
end
```

The arguments are `[left, top, right, bottom]` for the area you want to ignore.  You can also set this globally:

```ruby
Capybara::Screenshot::Diff.skip_area = [0, 0, 64, 48]
```

If you need to ignore multiple areas:

```ruby
screenshot 'index', skip_area: [[0, 0, 64, 48], [17, 6, 27, 16], 'css_selector .element']
```

### Skipping stack frames in the error output

If you would like to override the `screenshot` method or for some other reason would like to skip stack
frames when reporting image differences, you can use the `skip_stack_frames` option:

```ruby
test 'test visiting the index' do
  visit root_path
  screenshot :index
end

private

def screenshot(name, **options)
  super(name, skip_stack_frames: 1, **options)
end
```

### Screenshot Format

You can specify the format of the screenshots taken by setting the `screenshot_format` option. By default, the format is set to `"png"`. However, you can change this to any format supported by your image processing driver. For example, to set the format to `"webp"`, you can do the following:

```ruby
Capybara::Screenshot.screenshot_format = "webp"
```

### Customize Capybara#screenshot options

Allow to bypass screenshot options to Capybara driver.

```ruby
# To create full page screenshots for Selenium
Capybara::Screenshot.capybara_screenshot_options[:full_page] = true

screenshot('index', median_filter_window_size: 2, capybara_screenshot_options: {full_page: false})
```

[← Back to README](../README.md)
