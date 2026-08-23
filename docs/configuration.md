# Configuration Reference

## Quick Setup

Every setting lives on one flat object, `SnapDiff.config` (a `SnapDiff::Config`), and
`SnapDiff.configure` is the single way in.

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

Or set them one at a time:

```ruby
SnapDiff.config.window_size = [1280, 1024]
SnapDiff.config.tolerance          # => 0.0005
```

There are 25 settings, all of them on this object. The v1 two-holder form — the
`Capybara::Screenshot` / `Capybara::Screenshot::Diff` accessors and the
`Diff.configure { |screenshot, diff| }` block — was removed in 2.1; see
[UPGRADING.md](UPGRADING.md#upgrading-to-v21). The option names did not change, only the
receiver. The one exception: the old `Capybara::Screenshot.enabled` is
`SnapDiff.config.screenshot_enabled`, because `SnapDiff.config.enabled` is the old
`Capybara::Screenshot::Diff.enabled`. See
[SnapDiff — the canonical API](snapdiff.md) for the full object map.

**Note:** `fail_if_new` defaults to `true` in CI environments (when `ENV['CI']` is set). New screenshots are allowed locally but rejected in CI — no configuration needed.

**Note:** Setting `SnapDiff.config.screenshot_enabled = false` is sufficient to disable all screenshots. There is no need to define no-op modules or monkey-patch the gem.

## Recommended tolerance values

| Use Case | `tolerance` | `color_distance_limit` | `stability_time_limit` |
|----------|-------------|------------------------|----------------------|
| Animated/complex pages | 0.01 | 30 | 2s |
| Standard Rails apps | 0.001 (default) | 15 | 1s |
| Pixel-perfect design tests | 0.0001 | 5 | 1s |

**Note:** `tolerance` defaults to 0.001 (allows 0.1% pixel difference).

## Choosing the Right Color Comparison Method

**Important:** `perceptual_threshold`, `color_distance_limit`, and `tolerance` serve different purposes. Use this decision tree:

### Step 1: Choose color comparison method (pick ONE)

| Method | Scale | Best for |
|--------|-------|----------|
| `perceptual_threshold` | 0-100+ (dE00) | Cross-OS/browser font rendering, anti-aliasing |
| `color_distance_limit` | 0-510 (RGBA Euclidean) | Fine-grained RGB control |

**Recommendation:** Use `perceptual_threshold: 2.0` for most cases. It matches human perception and needs less tuning.

**⚠️ Color comparison methods are exclusive:** `perceptual_threshold` and `color_distance_limit` cannot both be active — if you set both, `perceptual_threshold` wins and `color_distance_limit` is ignored. However, `tolerance` works with **both** methods and is applied by default (0.001). This means even with `perceptual_threshold: 2.0`, the `tolerance: 0.001` default still filters results.

### Step 2: Set tolerance (optional, independent)

| Setting | What it does | Scale |
|---------|--------------|-------|
| `tolerance` | Maximum allowed *ratio* of different pixels | 0.0-1.0 |

**Example:** `tolerance: 0.001` allows 0.1% of the image to differ (e.g., 125 pixels in a 1280×1024 screenshot).

**Key difference:**
- `perceptual_threshold` / `color_distance_limit` → **"how different can a pixel be?"**
- `tolerance` → **"how many pixels can differ?"**

### Quick start

```ruby
# Modern approach (recommended)
screenshot 'dashboard', perceptual_threshold: 2.0

# Allow small noise regions
screenshot 'dashboard', perceptual_threshold: 2.0, tolerance: 0.001

# Raw RGB distance instead of perceptual
screenshot 'dashboard', color_distance_limit: 15
```

## Configuration Tiers

**Tier 1 — Zero config (works immediately):**
`blur_active_element`, `hide_caret`, and `fail_if_new` (in CI) are enabled by default.
Just `require 'snap_diff/integrations/minitest'` and call `screenshot`.

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
| `area_size_limit` | Allow small diff regions below a pixel count |
| `color_distance_limit` | Fine-tune raw RGB channel tolerance |
| `median_filter_window_size` | Smooth noise before comparison (per-screenshot option only) |

---

## Common Options

### Screen size

You can specify the desired screen size using

```ruby
SnapDiff.config.window_size = [1024, 768]
```

This will force the screen shots to the given size, and skip taking screen shots
unless the desired window size can be achieved.

### Disabling screen shots

If you want to skip taking screen shots, set

```ruby
SnapDiff.config.screenshot_enabled = false
```

You can of course set this by an environment variable

```ruby
SnapDiff.config.screenshot_enabled = ENV['TAKE_SCREENSHOTS']
```

### Disabling diff

If you want to skip the assertion for change in the screen shot, set

```ruby
SnapDiff.config.enabled = false
```

Using an environment variable

```ruby
SnapDiff.config.enabled = ENV['COMPARE_SCREENSHOTS']
```

### Tolerate screenshot differences

To allow screenshot differences, but still fail on functional errors, you can set the following option:

```ruby
SnapDiff.config.fail_on_difference = false
```

It defaults to `true`.  This can be useful in continuous integration to a generate a screenshot difference
report while still reporting functional errors.

### Does not tolerate new screenshots

To fail the test if a new screenshot is taken, set the following option:

```ruby
SnapDiff.config.fail_if_new = true
```

If `fail_if_new` is set to `true`, the test will fail if a new screenshot is taken
that does not have a corresponding previous image to compare against.
This can be useful in situations where you want to ensure
that every screenshot taken by your tests corresponds to an expected state of your application.

### Marks new screenshots as pending

To mark tests as pending (skipped) if a new screenshot is taken without a baseline, set:

```ruby
SnapDiff.config.pending_if_new = true
# Required in CI, because fail_if_new defaults to true there and raises before
# the pending marker is applied.
SnapDiff.config.fail_if_new = false
```

If `pending_if_new` is set to `true`, the test will be marked as skipped in teardown
when a new screenshot has no committed baseline to compare against.
This is complementary to `fail_if_new` (which raises immediately); `fail_if_new` takes precedence since it raises first.
This option is useful when you want to record new screenshots without blocking CI, but still track them as needing review.

### Screen shot save path

By default, SnapDiff saves screenshots to a
`doc/screenshots` folder, relative to either `Rails.root` (if you're in Rails),
or your current directory otherwise.

If you want to change where screenshots are saved to, then there are two
configuration options that that are relevant.

The most likely one you'll want to modify is ...

```ruby
SnapDiff.config.save_path = "other/path"
```

The `save_path` option is relative to `SnapDiff.config.root`.

`SnapDiff.config.root` defaults to either `Rails.root` (if you're in
Rails) or your current directory. You can change it to something entirely
different if necessary, such as when using an alternative web framework.

```ruby
SnapDiff.config.root = Hanami.root
```

### Screen shot stability

To ensure that animations are finished before saving a screen shot, you can add
a stability time limit.  If the stability time limit is set, a second screen
shot will be taken and compared to the first.  This is repeated until two
subsequent screen shots are identical.

```ruby
SnapDiff.config.stability_time_limit = 0.1
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
SnapDiff.config.hide_caret = true
```

This will make the cursor (caret) transparent (invisible), so the blinking does not delay the screen shot.


### Removing focus from the active element

Another way to avoid the cursor blinking is to set the `blur_active_element` option:

```ruby
SnapDiff.config.blur_active_element = true
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
SnapDiff.config.color_distance_limit = 42
```


### Allowed shift distance (removed in 2.1)

The `shift_distance_limit` option let you tolerate small movements in the image (for example,
jquery-tablesorter rendering the same table slightly differently each run). It was implemented
only by the ChunkyPNG driver, and 2.1 removed that driver — libvips is the only backend now,
and it has no shift-distance comparison.

Setting it anywhere is a `NoMethodError` on the config object and an ignored key per
screenshot. Use one of these instead:

| Instead of `shift_distance_limit` | Why |
|---|---|
| `median_filter_window_size` | The same idea, far faster — smooths the image before comparing. See [Image Processing](drivers.md#median-filter-size) |
| `tolerance` | Allows a ratio of the pixels to differ, wherever they are |
| `color_distance_limit` | Allows each pixel to differ by a colour distance |

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
SnapDiff.config.area_size_limit = 42
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
SnapDiff.config.skip_area = [0, 0, 64, 48]
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
SnapDiff.config.screenshot_format = "webp"
```

### Customize Capybara#screenshot options

Allow to bypass screenshot options to Capybara driver.

```ruby
# To create full page screenshots for Selenium
SnapDiff.config.capybara_screenshot_options[:full_page] = true

screenshot('index', median_filter_window_size: 2, capybara_screenshot_options: {full_page: false})
```

[← Back to README](../README.md)
