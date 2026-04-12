[![Gem Version](https://badge.fury.io/rb/capybara-screenshot-diff.svg)](https://rubygems.org/gems/capybara-screenshot-diff)
[![Test](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/test.yml/badge.svg)](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/test.yml)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-snap--diff%2Fsnap__diff--capybara-blue.svg?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggZD0iTTEyIDJhMTAgMTAgMCAxIDAgMCAyMCAxMCAxMCAwIDAgMCAwLTIweiIvPjxwYXRoIGQ9Ik0xMiA2djEyIi8+PHBhdGggZD0iTTYgMTJoMTIiLz48L3N2Zz4=)](https://deepwiki.com/snap-diff/snap_diff-capybara)

# Capybara::Screenshot::Diff

Catch visual regressions before they ship. Screenshots taken during tests are automatically compared against committed baselines — if the UI changed, the test fails.

## Quick Start

```ruby
# Gemfile
gem 'capybara-screenshot-diff'
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
bundle exec rake test                    # Second run compares against baselines
git add doc/screenshots/
git commit -m "chore: add screenshot baselines"
```

That's it. The first run saves baseline screenshots (always passes). Subsequent runs compare against them — if the UI changed, the test fails. Commit baselines to git so CI catches regressions.

> **CI note:** In CI, `fail_if_new` is `true` by default — new screenshots without a committed baseline will fail. Always commit your baselines before pushing.

For RSpec, Cucumber, or non-Rails setup, see [Framework Setup](docs/framework-setup.md).

## What You Get

When a screenshot differs, the test fails with a clear message:

```text
Screenshot does not match for 'homepage':
({"area_size":1250,"region":[0,19,199,83],"max_color_distance":42.5})
```

And generates diff files for inspection:

| File | Description |
|------|-------------|
| `homepage.png` | Committed baseline |
| `homepage.diff.png` | Visual diff with changes highlighted in red |
| `homepage.heatmap.diff.png` | Heatmap of pixel differences |

Enable the [HTML report](docs/reporters.md) for an interactive dashboard with side-by-side comparison, zoom, and annotation toggle.

**Compare any two images** without a browser — PDFs, generated images, CI artifacts:
```ruby
Capybara::Screenshot::Diff.compare("baseline.png", "current.png")
```

## Installation

```ruby
# Gemfile
gem 'capybara-screenshot-diff'

# Optional: faster image processing (recommended)
gem 'ruby-vips'
```

Then run `bundle install`.

**Requirements:** Ruby 3.2+, Rails 7.1+. For the `:vips` driver: [libvips 8.9+](https://libvips.github.io/libvips/install.html).

## Next Steps

- **Crop to element:** `screenshot "form", crop: "#main-form"`
- **Ignore regions:** `screenshot "dashboard", skip_area: [".timestamp"]`
- **Run in CI:** See [GitHub Actions setup](docs/ci-integration.md)
- **HTML report:** `require 'capybara_screenshot_diff/reporters/html'` — [details](docs/reporters.md)

## Tuning Flaky Tests

**Defaults work for most Rails apps.** `blur_active_element`, `hide_caret`, and `fail_if_new` (in CI) are enabled automatically.

If you see inconsistent results, choose a color comparison method:

```ruby
# Option 1: Perceptual (recommended, VIPS only)
Capybara::Screenshot::Diff.perceptual_threshold = 2.0

# Option 2: Raw RGB tolerance (legacy)
Capybara::Screenshot::Diff.tolerance = 0.0005

# Always set window_size for consistent dimensions
Capybara::Screenshot::Diff.configure do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
end
```

| Use Case | VIPS `perceptual_threshold` | VIPS `tolerance` | ChunkyPNG `color_distance_limit` |
|----------|---------------------------|-----------------|--------------------------------|
| Cross-OS/browser testing | 2.0 (recommended) | — | — |
| Standard Rails apps | — | 0.001 (default) | 15 |
| Animated/complex pages | — | 0.01 | 30 |
| Pixel-perfect design | — | 0.0001 | 5 |

**⚠️ Color methods are exclusive:** Use `perceptual_threshold` OR `color_distance_limit`, not both. But `tolerance` works with either — it's applied by default for VIPS (0.001). See [Choosing the Right Method](docs/configuration.md#choosing-the-right-color-comparison-method).

## Troubleshooting

**"No existing screenshot found"** — First run saves baselines. Run `bundle exec rake test` twice, then commit `doc/screenshots/`.

**Screenshots differ between CI and local** — Use `tolerance: 0.001` or `perceptual_threshold: 2.0`. Set `window_size` for consistent dimensions.

**Animations cause flaky diffs** — `Capybara.disable_animation = true`, or `stability_time_limit: 1`.

**Dynamic content always differs** — `screenshot "page", skip_area: [".timestamp", "#ad-banner"]`

**Debug mode** — `DEBUG=1 bundle exec rake test` keeps `.diff.png` files for inspection.

## Advanced Topics

- [Framework Setup](docs/framework-setup.md) — Minitest, RSpec, Cucumber
- [Image Processing Drivers](docs/drivers.md) — VIPS, ChunkyPNG, perceptual threshold
- [Screenshot Organization](docs/organization.md) — groups, sections, cropping, multi-browser
- [Configuration Reference](docs/configuration.md) — all options explained
- [Reporters](docs/reporters.md) — HTML report, custom reporters
- [CI & Non-Rails Integration](docs/ci-integration.md) — GitHub Actions, reusable action, baseline updates
- [Docker Testing](docs/docker-testing.md) — bin/dtest, recording baselines

## Development

After checking out the repo, run `bin/setup` then `rake test`. See [Docker Testing](docs/docker-testing.md) for reproducible CI-matching test runs.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
