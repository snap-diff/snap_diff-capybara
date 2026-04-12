# Image Processing Drivers

## Perceptual color comparison (VIPS only)

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
Capybara::Screenshot::Diff.perceptual_threshold = 2.0

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

**Choose one based on your driver setup:**
- VIPS with `ruby-vips` gem → prefer `perceptual_threshold`
- ChunkyPNG (no native dependencies) → use `color_distance_limit`

## Available Image Processing Drivers

There are several image processing supported by this gem.
There are several options to setup active driver: `:auto`, `:chunky_png` and `:vips`.

* `:auto` - will try to load `:vips` if there is gem `ruby-vips`, in other cases will load `:chunky_png`
* `:chunky_png` and `:vips` will load correspondent driver

## Enable VIPS image processing

[Vips](https://www.rubydoc.info/gems/ruby-vips/Vips/Image) driver provides a faster comparison,
and could be enabled by adding `ruby-vips` to `Gemfile`.

If need to setup explicitly Vips driver, there are several ways to do this:

* Globally: `Capybara::Screenshot::Diff.driver = :vips`
* Per screenshot option: `screenshot 'index', driver: :vips`

With enabled VIPS there are new alternatives to process differences, which are easier to find and support.
For example, `shift_distance_limit` is a very heavy operation. Instead, use `median_filter_window_size`.

## Tolerance level (vips only)

You can set a "tolerance" anywhere from 0% to 100%. This is the amount of change that's allowable.
If the screenshot has changed by more than that amount, it'll flag it as a failure.

This is alternative to "Allowed difference size", only the difference that area calculates including valid pixels.
But "tolerance" compares only different pixels.

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
# Default for VIPS is 0.001 (0.1% pixel difference allowed)
Capybara::Screenshot::Diff.tolerance = 0.001
```

## Median filter size (vips only)

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
