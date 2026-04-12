[![Gem Version](https://badge.fury.io/rb/capybara-screenshot-diff.svg)](https://rubygems.org/gems/capybara-screenshot-diff)
[![Test](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/test.yml/badge.svg)](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/test.yml)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-snap--diff%2Fsnap__diff--capybara-blue.svg?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggZD0iTTEyIDJhMTAgMTAgMCAxIDAgMCAyMCAxMCAxMCAwIDAgMCAwLTIweiIvPjxwYXRoIGQ9Ik0xMiA2djEyIi8+PHBhdGggZD0iTTYgMTJoMTIiLz48L3N2Zz4=)](https://deepwiki.com/snap-diff/snap_diff-capybara)

# Capybara::Screenshot::Diff

Stop shipping UI bugs. Take screenshots in your Rails tests, commit baselines to git, and let CI catch visual regressions in pull requests — no cloud service, no subscription, runs entirely in your test suite.

**Why this gem?** Percy and Chromatic cost money and send your screenshots to a third party. BackstopJS requires Node. This gem integrates directly into your Capybara tests, stores baselines in git, and works offline.

## Quick Start

```ruby
# Gemfile
gem 'capybara-screenshot-diff'
gem 'ruby-vips'  # Optional: 10x faster comparisons
```

```ruby
# test/test_helper.rb
require 'capybara_screenshot_diff/minitest'
```

```ruby
# test/application_system_test_case.rb
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include CapybaraScreenshotDiff::Minitest::Assertions
end
```

```ruby
# test/system/homepage_test.rb
class HomepageTest < ApplicationSystemTestCase
  test "homepage" do
    visit "/"
    screenshot "homepage"
  end
end
```

```bash
bundle exec rake test                    # First run always passes — saves baselines
git add doc/screenshots/
git commit -m "chore: add screenshot baselines"
bundle exec rake test                    # Second run compares against committed baselines
```

First run saves baseline screenshots to `doc/screenshots/` (always passes). Commit them to git. Subsequent runs compare against committed baselines — if the UI changed, the test fails.

> **CI note:** `fail_if_new` is `true` by default in CI — new screenshots without a committed baseline will fail. Always commit baselines before pushing.

For RSpec, Cucumber, or non-Rails setup, see [Framework Setup](docs/framework-setup.md).

## What Happens When a Screenshot Changes

The test fails with a clear message and generates diff files:

```text
Screenshot does not match for 'homepage':
({"area_size":1250,"region":[0,19,199,83],"max_color_distance":42.5})
```

Open `doc/screenshots/homepage.diff.png` to see exactly what changed. If the change is intentional, delete the baseline and re-run to update it.

| File | Description |
|------|-------------|
| `homepage.png` | Committed baseline |
| `homepage.diff.png` | Visual diff with changes highlighted in red |
| `homepage.heatmap.diff.png` | Heatmap of pixel differences |

## Web UI for Reviewing Screenshot Changes

Add one line to get an interactive dashboard for reviewing all screenshot differences:

```ruby
# test/test_helper.rb
require 'capybara_screenshot_diff/reporters/html'
```

After tests run, open `doc/screenshots/snap_diff_report.html` — side-by-side comparison with 4 view modes (both/base/new/heatmap), per-image zoom, annotation toggle, keyboard navigation, and search.

**In GitHub Actions**, the report renders inline as a CI artifact — no download needed. Add a PR comment with a link to the report automatically:

```yaml
- name: Upload screenshot report
  if: failure()
  uses: snap-diff/snap_diff-capybara/.github/actions/upload-screenshots@master
  with:
    name: screenshots
```

See [CI Integration](docs/ci-integration.md) for the full GitHub Actions setup with PR commenting.

## Compare Any Two Images

Works without a browser — PDFs, generated images, CI artifacts:

```ruby
result = Capybara::Screenshot::Diff.compare("baseline.png", "current.png")
result.different?    # => true if visually different
result.quick_equal?  # => true if byte-identical
```

## Next Steps

- **Crop to element:** `screenshot "form", crop: "#main-form"`
- **Ignore regions:** `screenshot "dashboard", skip_area: [".timestamp"]`
- **Disable animations:** `Capybara::Screenshot.disable_animations = true`
- **Set window size:** `Capybara::Screenshot.window_size = [1280, 1024]`

## Handling Flaky Tests

Defaults work for most Rails apps — `blur_active_element`, `hide_caret`, and `fail_if_new` (in CI) are enabled automatically.

If screenshots differ between CI and local, set a comparison threshold:

```ruby
Capybara::Screenshot::Diff.configure do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
  diff.perceptual_threshold = 2.0   # Recommended for VIPS — ignores anti-aliasing
  # or: diff.tolerance = 0.001      # Default for VIPS, percentage-based
end
```

See [Choosing the Right Method](docs/configuration.md#choosing-the-right-color-comparison-method) for detailed comparison options.

## Common Questions

**Why did my test pass on the first run?** First run always passes and saves baselines. Run again to compare.

**How do I update baselines?** Delete the baseline file and re-run tests. Or delete all: `rm -rf doc/screenshots/ && bundle exec rake test`.

**Animations make screenshots flaky** — `Capybara::Screenshot.disable_animations = true` freezes CSS animations/transitions before each capture.

**CI screenshots differ from local** — Set `window_size` for consistent dimensions and use `perceptual_threshold: 2.0` to ignore rendering differences.

**Debug mode** — `DEBUG=1 bundle exec rake test` keeps `.diff.png` files for inspection.

## Installation

**Requirements:** Ruby 3.2+, Rails 7.1+. For the `:vips` driver: [libvips 8.9+](https://libvips.github.io/libvips/install.html).

## Advanced Topics

- [Framework Setup](docs/framework-setup.md) — Minitest, RSpec, Cucumber
- [Image Processing Drivers](docs/drivers.md) — VIPS, ChunkyPNG, perceptual threshold
- [Screenshot Organization](docs/organization.md) — groups, sections, cropping, multi-browser
- [Configuration Reference](docs/configuration.md) — all options explained
- [Web UI & Custom Reporters](docs/reporters.md) — interactive report, custom reporters
- [CI & Non-Rails Integration](docs/ci-integration.md) — GitHub Actions, reusable action, baseline updates
- [Docker Testing](docs/docker-testing.md) — bin/dtest, recording baselines

## Development

After checking out the repo, run `bin/setup` then `rake test`. See [Docker Testing](docs/docker-testing.md) for reproducible CI-matching test runs.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
