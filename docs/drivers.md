# Image Processing

Comparison runs on [libvips](https://www.libvips.org/) through the
[`ruby-vips`](https://www.rubydoc.info/gems/ruby-vips/Vips/Image) gem. There is nothing to
configure and nothing to choose: `ruby-vips` is a runtime dependency of this gem, so Bundler
installs it for you.

**libvips itself is a system library** and is not installed by Bundler. Add it with your
package manager:

```sh
brew install vips           # macOS
apt-get install libvips     # Debian/Ubuntu
```

## Removed in 2.1: the driver abstraction

2.0 shipped two backends and a way to pick between them. 2.1 removed the choice.

| Removed in 2.1 | What to do instead |
|---|---|
| the `:chunky_png` driver | install libvips (above); comparisons run on it automatically |
| the `driver:` setting and `driver: :auto` | delete the line — there is one backend |
| `shift_distance_limit` | ChunkyPNG-only, with no libvips equivalent. Use `median_filter_window_size`, `tolerance` or `color_distance_limit` |
| `SnapDiff::Driver` (the custom-driver mixin) | nothing — see below |
| `SnapDiff::Drivers.loaded` (the registry) | nothing — see below |
| `SnapDiff::Drivers.available` / `SnapDiff::Utils.detect_available_drivers` | nothing to detect; a missing `ruby-vips` is now a Bundler resolution error |

`SnapDiff::Drivers::VipsDriver` is the one name from this area that survives, and it is
internal: nothing in normal use has to mention it.

**Custom drivers: there is no migration path.** The abstraction is removed whole — the
mixin, the registry, and selection by name. Third-party drivers stop working and nothing
replaces them. This was deliberate: one backend is what keeps the comparison engine honest.
If you maintain one, say so on
[the issue tracker](https://github.com/snap-diff/snap_diff-capybara/issues).

## Perceptual color comparison

By default, color differences are measured using raw RGB channel distance. This can produce
false positives from anti-aliasing and sub-pixel font rendering — the same page rendered on
different OS versions or browsers will have slightly different pixel values at text edges.

The `perceptual_threshold` option uses the CIE dE00 formula instead, which measures color
difference the way human eyes perceive it. Anti-aliasing artifacts typically score below 2.0
on the dE00 scale and are automatically ignored.

```ruby
# Per-screenshot: ignore anti-aliasing, catch real visual changes
screenshot 'dashboard', perceptual_threshold: 2.0

# Global: apply to all screenshots
SnapDiff.config.perceptual_threshold = 2.0

# dE00 scale reference:
#   < 1.0  — not perceptible by human eyes
#   1-2    — perceptible through close observation (anti-aliasing, font hinting)
#   2-10   — perceptible at a glance (color shifts, layout changes)
#   > 10   — clearly different colors
```

Use `perceptual_threshold` when you see false positives from font rendering differences across
CI environments, or when `color_distance_limit` with raw RGB requires frequent tuning.

**⚠️ Important:** `perceptual_threshold` and `color_distance_limit` are **mutually exclusive**.
If you set both, `perceptual_threshold` takes priority and `color_distance_limit` is silently ignored.

These options use different scales and algorithms:
- `perceptual_threshold` → CIE dE00 perceptual distance (0-100+)
- `color_distance_limit` → Euclidean RGBA distance (0-510)

## Tolerance level

You can set a "tolerance" anywhere from 0% to 100%. This is the amount of change that's allowable.
If the screenshot has changed by more than that amount, it'll flag it as a failure.

This is an alternative to "Allowed difference size", where the difference area is calculated
including valid pixels. "Tolerance" compares only different pixels.

You can use the `tolerance` option to the `screenshot` method to set level:

```ruby
test 'unstable area' do
  visit '/'
  # tolerance: 0.01 allows 1% of pixels to differ (use for noisy pages)
  screenshot 'index', tolerance: 0.01
end
```

You can also set this globally:

```ruby
# Default is 0.001 (0.1% pixel difference allowed)
SnapDiff.config.tolerance = 0.001
```

## Median filter size

This is an alternative to "Allowed shift distance", but much faster.
You can find more about this strategy on [Median Filter](https://en.wikipedia.org/wiki/Median_filter).
Think about this like smoothing of the image, before comparison.

You can use the `median_filter_window_size` option to the `screenshot` method to set level:

```ruby
test 'unstable area' do
  visit '/'
  screenshot 'index', median_filter_window_size: 2
end
```

[← Back to README](../README.md)
