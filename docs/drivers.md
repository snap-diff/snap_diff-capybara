# Image Processing Drivers

> **Canonical equivalents.** Global settings shown here as
> `Capybara::Screenshot::Diff.<option> = …` are also `SnapDiff.config.<option> = …` — same
> option names, same storage, either surface works. Writing your own driver? See
> [Custom drivers](snapdiff.md#custom-drivers) for the `SnapDiff::Driver` mixin and how
> registration in `SnapDiff::Drivers.loaded` works.

## Removed in 2.1: everything on this page except VIPS

2.1 makes **libvips the only backend**. 2.0 is the transitional release — all of the
following still works. Most of it warns once per process naming 2.1; the rows marked
*silent* cannot warn, and this table is their notice. Silence the warnings with
`SnapDiff.silence_deprecations = true` or `SNAP_DIFF_SILENCE_DEPRECATIONS=1`.

| Removed in 2.1 | What to do in 2.0 |
|---|---|
| the `:chunky_png` driver | add `gem "ruby-vips"` to your Gemfile and drop `driver: :chunky_png` |
| the `driver:` setting itself — `SnapDiff.config.driver =` and the legacy `Capybara::Screenshot::Diff.driver =` (**silent in 2.0**; on 2.1 they raise `NoMethodError` at config time) | delete the line; one backend needs no selection |
| the per-screenshot `driver:` override — `screenshot "index", driver: :vips` (**silent in 2.0 *and* 2.1**: per-screenshot options are a free-form hash, so an unknown key is simply inert) | delete the option, and grep for it — nothing will tell you the line is dead |
| `driver: :auto` (and the `:auto` default) — warns **only when `:auto` actually falls back to ChunkyPNG**, i.e. when `ruby-vips` is missing; **silent** otherwise | with one backend there is nothing to choose; install `ruby-vips` and the default just works |
| `shift_distance_limit` | ChunkyPNG-only. Use `median_filter_window_size`, `tolerance` or `color_distance_limit` — see [Configuration](configuration.md#allowed-shift-distance) |
| `SnapDiff::Driver` (the custom-driver mixin) | nothing — see below |
| `SnapDiff::Drivers.loaded` (the registry) | nothing — see below |
| `SnapDiff::Drivers.available` (driver detection) | require `ruby-vips` instead of branching on a detected list |

Three related names on the same chopping block stay **silent**, and deliberately so:
`SnapDiff::Drivers.for` (the gem calls it for every comparison — warning there would fire on
setups that nothing in this table affects), `SnapDiff::Drivers.detect_available` /
`SnapDiff::Utils.detect_available_drivers` (run at load, before any user code), and the legacy
`Capybara::Screenshot::Diff::LOADED_DRIVERS` / `::AVAILABLE_DRIVERS` constant aliases (plain
constants, nothing to hook). Reach the same values through `.loaded` / `.available` and you
will hear about them.

**libvips becomes a hard requirement.** Install it with your system package manager
(`brew install vips`, `apt-get install libvips`) and add `gem "ruby-vips"`. A 2.1 process
without it cannot compare images at all.

**Custom drivers: there is no migration path.** The driver abstraction is removed whole —
the `SnapDiff::Driver` mixin, the `SnapDiff::Drivers.loaded` registry, and driver
selection by name. Third-party drivers stop working in 2.1 and nothing replaces them
(the decision was made deliberately: no measurable demand, and one backend is what keeps
the comparison engine honest). If you maintain one, say so on
[the issue tracker](https://github.com/snap-diff/snap_diff-capybara/issues) before 2.1
ships — that is the only thing that can change this.

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

> **2.1 keeps only `:vips`.** `:auto` and `:chunky_png` are removed; each warns once per
> process in 2.0. If `:auto` is quietly running you on ChunkyPNG today (no `ruby-vips`
> installed), the warning says so — that is the setup 2.1 breaks.

## Enable VIPS image processing

[Vips](https://www.rubydoc.info/gems/ruby-vips/Vips/Image) driver provides a faster comparison,
and is enabled by adding `ruby-vips` to your `Gemfile` (plus the libvips system package).
That is the whole setup — with `ruby-vips` installed the default `:auto` already picks it.

**Do not select it explicitly.** Both forms are on the 2.1 removal list at the top of this page:
`Capybara::Screenshot::Diff.driver = :vips` / `SnapDiff.config.driver = :vips` raises
`NoMethodError` at config time on 2.1, and the per-screenshot `screenshot 'index', driver: :vips`
becomes inert. Neither warns in 2.0 — delete the line and grep for the per-screenshot form.

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
