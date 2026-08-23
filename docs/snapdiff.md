# SnapDiff — the canonical API

Everything in this gem lives under `SnapDiff` since v2. This page is the SnapDiff-native
reference: setup, configuration, the object map, and the extension points — all using canonical
names only.

The legacy `Capybara::Screenshot::Diff` / `CapybaraScreenshotDiff` names still work — they resolve
to the same objects — and the rest of the docs still teach them. The first legacy API a process
touches prints one migration notice; on top of that, *lazily shimmed* constants warn once each.
Some legacy names are silent by design. [UPGRADING.md](UPGRADING.md#deprecation-warnings) lists
exactly which is which. Nothing here replaces a working setup — it is what you write for **new** code.
For migrating an existing suite, see [UPGRADING.md](UPGRADING.md).

## Quick start

### Minitest

```ruby
# test/test_helper.rb
require "snap_diff/integrations/minitest"
```

```ruby
# test/application_system_test_case.rb
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include SnapDiff::Minitest::Assertions   # brings in SnapDiff::DSL too
end
```

```ruby
class HomepageTest < ApplicationSystemTestCase
  test "homepage" do
    visit "/"
    assert_matches_screenshot "homepage"
  end
end
```

`SnapDiff::Minitest::Assertions` already includes `SnapDiff::DSL`, so a separate
`include SnapDiff::DSL` is not needed (it is harmless if you have it).

> **The require path is `snap_diff/integrations/…`, not `snap_diff/…`.**
> `require "snap_diff/minitest"` raises `LoadError` — there is no such file. The integrations
> live one level down, mirroring `lib/snap_diff/integrations/`.

### RSpec

```ruby
# spec/rails_helper.rb
require "snap_diff/integrations/rspec"
```

This registers the `match_screenshot` matcher and includes `SnapDiff::DSL` into
`type: :feature` and `type: :system` examples automatically:

```ruby
RSpec.describe "Homepage", type: :system do
  it "looks right" do
    visit "/"
    expect(page).to match_screenshot("homepage")
  end
end
```

For other example types, include the DSL yourself:

```ruby
RSpec.describe "Admin", type: :request do
  include SnapDiff::DSL
end
```

### Cucumber

```ruby
# features/support/env.rb
require "snap_diff/integrations/cucumber"
```

The DSL is added to the Cucumber `World`, so steps can call `screenshot` /
`assert_matches_screenshot` directly. This file must be loaded from inside a Cucumber run — it
calls `World`, `Before`, `After` and `AfterAll` at load time and raises `NoMethodError` if
required outside one.

### Static sites (Hugo, Jekyll, plain HTML)

```ruby
require "snap_diff/static"

SnapDiff.serve("_site")             # or "public", "build", "dist"
SnapDiff.serve("_site", root: Dir.pwd)   # root defaults to Dir.pwd
```

`SnapDiff.serve` points Capybara at the built directory and sets the screenshot root. It also
loads the Minitest integration. See
[CI & Non-Rails Integration](ci-integration.md#non-rails-projects-hugo-jekyll-static-sites).

## Configuration

All 27 settings live on one flat object, `SnapDiff.config` (a `SnapDiff::Config`).

```ruby
# test_helper.rb / rails_helper.rb
SnapDiff.configure do |config|
  config.window_size = [1280, 1024]
  config.tolerance = 0.0005
  config.driver = :vips
  config.save_path = "doc/screenshots"
end

# Or set them one at a time
SnapDiff.config.hide_caret = true
SnapDiff.config.tolerance          # => 0.0005
```

`SnapDiff::Config` **is** the storage. The legacy `Capybara::Screenshot.*` and
`Capybara::Screenshot::Diff.*` accessors are thin delegators onto it — one storage, two views —
so a write through either surface is immediately visible through the other:

```ruby
SnapDiff.config.window_size = [1280, 1024]
Capybara::Screenshot.window_size    # => [1280, 1024]
```

`SnapDiff.start` is the same call shape as the old `Capybara::Screenshot::Diff.configure`, if
you prefer the two-holder form:

```ruby
SnapDiff.start do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
  diff.tolerance = 0.0005
end
```

Three derived, read-only values are computed from the settings above:

| Method | What it returns |
|--------|-----------------|
| `SnapDiff.config.active?` | Whether screenshots are taken at all (ex `Capybara::Screenshot.active?`) |
| `SnapDiff.config.screenshot_area` | `save_path`, optionally segmented per OS and per Capybara driver |
| `SnapDiff.config.default_options` | The capture/compare defaults handed to `SnapDiff::Comparison` |

Every option's meaning is documented in the
[Configuration Reference](configuration.md) — the names are identical, only the receiver differs.
The one rename: `Capybara::Screenshot.enabled` is `SnapDiff.config.screenshot_enabled`, because
`SnapDiff.config.enabled` is taken by `Capybara::Screenshot::Diff.enabled`.

## Object map

`require "snap_diff"` gives you the compare/configure core. The test-suite pieces come with the
integration require; a few objects need their own require, noted below.

| Object | What it is for |
|--------|----------------|
| `SnapDiff.config`, `SnapDiff::Config` | Every setting, one flat object. The storage. |
| `SnapDiff.configure`, `SnapDiff.start` | Config block helpers (consolidated / v1 shape) |
| `SnapDiff.compare` | Compare two image files directly, no browser |
| `SnapDiff::Comparison` | The layered comparison engine (ex `ImageCompare`) |
| `SnapDiff::Comparison::Images` | Frozen bundle a comparison operates on: both images, their paths, the driver and the options |
| `SnapDiff::ComparisonResult` | Result value object: `different?`, region, metadata (ex `Difference`) |
| `SnapDiff::Region` | Bounding box value object — `from_edge_coordinates`, `to_edge_coordinates` |
| `SnapDiff::DSL` | `screenshot`, `assert_matches_screenshot`, `capture_screenshot`, groups/sections |
| `SnapDiff::Minitest::Assertions` | Minitest wiring (`snap_diff/integrations/minitest`) |
| `SnapDiff::Error` | Base class for every error this gem raises |
| `SnapDiff::ExpectationNotMet` | A screenshot did not match its baseline |
| `SnapDiff::UnstableImage` | No stable capture within `stability_time_limit` / `wait` |
| `SnapDiff::WindowSizeMismatchError` | Browser window is not the configured `window_size` |
| `SnapDiff::Driver` | Mixin with the shared driver defaults (`require "snap_diff/driver"`) |
| `SnapDiff::Drivers` | Driver factory and registry — `.for`, `.loaded`, `.available` |
| `SnapDiff::Reporting` | Process-global reporter lifecycle (`require "snap_diff/reporting"`) |
| `SnapDiff::Reporters::HTML` | The interactive HTML report (`require "snap_diff/reporters/html"`) |
| `SnapDiff::Reporters::Default` | Builds the annotated diff images and the failure message |
| `SnapDiff.session` | The per-test assertion registry (fiber-local) |
| `SnapDiff.reset` | Ends a test: notifies reporters, clears the session |
| `SnapDiff.pending_screenshots_message` | Skip message when a new screenshot has no baseline |
| `SnapDiff::Capture::Viewport` | Per-capture viewport check seam (`require "snap_diff/capture/viewport"`) |
| `SnapDiff.serve` | Point Capybara at a static site directory (`require "snap_diff/static"`) |

## Compare two images without a browser

Works on anything on disk — rendered PDFs, generated charts, CI artifacts:

```ruby
require "snap_diff"

result = SnapDiff.compare("baseline.png", "current.png")
result.quick_equal?   # => true when byte-identical / pixel-identical
result.different?     # => true when the difference exceeds the configured thresholds
result.difference     # => SnapDiff::ComparisonResult with region and metadata

# Per-call option overrides, merged over SnapDiff.config.default_options
SnapDiff.compare("baseline.png", "current.png", tolerance: 0.5)
```

Note the argument order: baseline first, current second ("compare baseline against current").

## Custom reporters

A reporter is any object answering `record(assertions)`, `finalize`, and `summary`. Register it
once, for the rest of the process:

```ruby
require "snap_diff/reporting"

class SlackReporter
  def initialize = @failures = []

  # Called once per finished test, with that test's assertions.
  def record(assertions)
    assertions.each do |assertion|
      next unless assertion.compare&.difference&.different?
      @failures << assertion.name
    end
  end

  # Called once at end of suite.
  def finalize
    post_to_slack(@failures) unless @failures.empty?
  end

  # Printed to stdout after finalize. Return nil to print nothing.
  def summary
    @failures.empty? ? nil : "#{@failures.size} screenshot(s) changed"
  end
end

SnapDiff::Reporting.register(SlackReporter.new)
```

`register` appends under a mutex, so concurrent registrations cannot lose one — prefer it over
mutating `SnapDiff::Reporting.reporters` directly.

Do implement `summary`. `finalize!` calls it unconditionally; a reporter without it is finalized
and then warned about (`[snap_diff] Reporter … failed (NoMethodError: undefined method 'summary')`).

A reporter that raises is warned about and skipped — the other reporters still run.

The bundled HTML report is just a pre-registered reporter of this kind:

```ruby
require "snap_diff/reporters/html"   # registers SnapDiff::Reporters::HTML itself
```

### Frameworks other than Minitest/RSpec/Cucumber

The three bundled integrations call the lifecycle for you. Wiring another framework means calling
three things:

```ruby
require "snap_diff/dsl"        # SnapDiff::DSL, BrowserHelpers, the session accessors
require "snap_diff/reporting"  # SnapDiff::Reporting

# before each test
SnapDiff::BrowserHelpers.resize_window_if_needed

# after each test
SnapDiff.session.verify                  # raises SnapDiff::ExpectationNotMet on a mismatch
msg = SnapDiff.pending_screenshots_message  # non-nil => skip the test with this message
SnapDiff.reset                           # always: notifies reporters, clears the session

# after the suite
SnapDiff::Reporting.finalize!
```

## Custom drivers

A driver is a plain object that does the image work. Include `SnapDiff::Driver` for the shared
defaults, then implement the operations the comparison engine calls:

```ruby
require "snap_diff/driver"

class MyDriver
  include SnapDiff::Driver

  # Provided by the mixin, override only if your image objects differ:
  #   width_for(image), height_for(image), dimension(image),
  #   image_area_size(image), same_dimension?(comparison), supports?(feature)

  # Implement (this is what both bundled drivers implement):
  #   from_file(path), load_images(base_path, new_path), save_image_to(image, path)
  #   same_pixels?(comparison), find_difference_region(comparison)
  #   crop(region, image), resize_image_to(image, w, h)
  #   add_black_box(image, region), draw_rectangles(images, region, ...)
end
```

`supports?(feature)` is just `respond_to?(feature)` — the engine uses it to skip optional
operations. The VIPS driver additionally implements `filter_image_with_median`, `merge`,
`highlight_mask` and `difference_level`; ChunkyPNG does not, and `supports?` is how that is
detected. Look at `lib/snap_diff/drivers/chunky_png_driver.rb` for the smaller of the two
reference implementations.

### Registration

`SnapDiff::Drivers.loaded` is the registry: a mutable `name => driver class` hash. Register by
writing into it, then select the driver by that name:

```ruby
SnapDiff::Drivers.loaded[:my_driver] = MyDriver

SnapDiff.config.driver = :my_driver          # globally
screenshot "index", driver: :my_driver       # or per screenshot
```

Resolution goes through `SnapDiff::Drivers.for`, which looks the symbol up in `loaded` and calls
`.new` on the class — **your driver class must be instantiable with no arguments**. A pre-built
instance skips the registry entirely:

```ruby
screenshot "index", driver: MyDriver.new     # any non-Symbol is used as-is
```

`SnapDiff::Drivers.available` is the *detected* list (`[:vips, :chunky_png]`, filled at load time
by probing for the `ruby-vips` and `chunky_png` gems). It is a read-only view of detection, not
the registry — registering a custom driver does not add it there, and `driver: :auto` picks
`available.first`. Custom drivers must always be named explicitly.

## Related

- [Framework Setup](framework-setup.md) — the same three integrations under their legacy names
- [Configuration Reference](configuration.md) — what every option does
- [Image Processing Drivers](drivers.md) — VIPS vs ChunkyPNG, perceptual threshold
- [Web UI & Custom Reporters](reporters.md) — the HTML report in detail
- [Architecture](architecture.md) — how the pieces fit together internally
- [UPGRADING.md](UPGRADING.md) — migrating an existing suite off the legacy names

[← Back to README](../README.md)
