# SnapDiff — the canonical API

Everything in this gem lives under `SnapDiff`. This page is the reference: setup, configuration,
the object map, and the extension points.

2.1 deleted the v1 `Capybara::Screenshot::Diff` / `CapybaraScreenshotDiff` namespaces outright —
they are `NameError`s now, not deprecations. Migrating a suite that still uses them? See
[UPGRADING.md](UPGRADING.md#upgrading-to-v21).

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

All 25 settings live on one flat object, `SnapDiff.config` (a `SnapDiff::Config`).

```ruby
# test_helper.rb / rails_helper.rb
SnapDiff.configure do |config|
  config.window_size = [1280, 1024]
  config.tolerance = 0.0005
  config.save_path = "doc/screenshots"
end

# Or set them one at a time
SnapDiff.config.hide_caret = true
SnapDiff.config.tolerance          # => 0.0005
```

`SnapDiff::Config` **is** the storage — one eagerly-created instance, every setting a plain
`attr_accessor`. There is no second view of it: the v1 `Capybara::Screenshot.*` /
`Capybara::Screenshot::Diff.*` delegators and the two-holder `SnapDiff.start` block were removed
in 2.1.

Three derived, read-only values are computed from the settings above:

| Method | What it returns |
|--------|-----------------|
| `SnapDiff.config.active?` | Whether screenshots are taken at all (ex `Capybara::Screenshot.active?`) |
| `SnapDiff.config.screenshot_area` | `save_path`, optionally segmented per OS and per Capybara driver |
| `SnapDiff.config.default_options` | The capture/compare defaults handed to `SnapDiff::Comparison` |

Every option's meaning is documented in the
[Configuration Reference](configuration.md). One name differs from its v1 spelling:
`screenshot_enabled` is the old `Capybara::Screenshot.enabled`, because the bare `enabled` is
taken by the old `Capybara::Screenshot::Diff.enabled`.

## Object map

`require "snap_diff"` gives you the compare/configure core. The test-suite pieces come with the
integration require; a few objects need their own require, noted below.

| Object | What it is for |
|--------|----------------|
| `SnapDiff.config`, `SnapDiff::Config` | Every setting, one flat object. The storage. |
| `SnapDiff.configure` | Config block helper — the single config entry point |
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

## Custom drivers — removed in 2.1

**There is no migration path, and that is deliberate.** 2.1 removed the driver abstraction
whole: the `SnapDiff::Driver` mixin, the `SnapDiff::Drivers.loaded` registry,
`SnapDiff::Drivers.available` detection, the `driver:` setting, and `driver: :auto`. libvips
is the only backend, `ruby-vips` is a runtime dependency of this gem, and
`SnapDiff::Drivers::VipsDriver` is wired in directly.

A third-party driver stops working on 2.1 and nothing replaces it. One backend is what keeps
the comparison engine honest — every option means one thing, and the reported figures come
from one implementation. If you maintain a driver, say so on
[the issue tracker](https://github.com/snap-diff/snap_diff-capybara/issues); that is the only
thing that can reopen this.

Everything the abstraction was used for from the outside has a direct answer:

| You used | Now |
|---|---|
| `SnapDiff.config.driver = :vips` | delete the line |
| `screenshot "index", driver: :vips` | delete the option |
| `driver: :auto` | delete it — there is one backend |
| `SnapDiff::Drivers.available` to branch on what is installed | nothing to branch on; a missing `ruby-vips` is a Bundler resolution error |
| `SnapDiff::Drivers.loaded[:mine] = MyDriver` | no replacement |

## Related

- [Framework Setup](framework-setup.md) — the three integrations, one page each
- [Configuration Reference](configuration.md) — what every option does
- [Image Processing](drivers.md) — libvips, perceptual threshold, tolerance
- [Web UI & Custom Reporters](reporters.md) — the HTML report in detail
- [Architecture](architecture.md) — how the pieces fit together internally
- [UPGRADING.md](UPGRADING.md) — migrating an existing suite off the legacy names

[← Back to README](../README.md)
