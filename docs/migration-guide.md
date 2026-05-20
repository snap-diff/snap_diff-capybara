# Migration Guide

Migrate your visual regression testing from other tools to `capybara-screenshot-diff`. This guide covers the most common migration paths.

## Why Switch?

| Factor | Percy / Chromatic | BackstopJS | `capybara-screenshot-diff` |
|--------|-------------------|------------|--------------------------|
| Pricing | Paid SaaS (snapshot limits) | Free | Free (MIT) |
| Infrastructure | Cloud service, API tokens | Node + Puppeteer | Ruby gem, no external services |
| Baselines | Hosted on their servers | Local files | Git (committed to repo) |
| Review | Web dashboard | HTML report | HTML report + GitHub PR comments |
| PR integration | GitHub app | Manual CI steps | Reusable GitHub Action |
| Offline | ❌ Requires internet | ✅ | ✅ |
| Diff in PRs | Screenshot in comment | Manual | Upload artifact + PR comment |

## From Percy

### Setup changes

**Before (Percy):**
```ruby
# Gemfile
gem 'percy-capybara'

# test helper
require 'percy/capybara'

# test
def test_homepage
  visit '/'
  Percy::Capybara.screenshot('homepage')
end
```

**After (capybara-screenshot-diff):**
```ruby
# Gemfile
gem 'capybara-screenshot-diff'

# test helper
require 'capybara_screenshot_diff/minitest'

# test class
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include CapybaraScreenshotDiff::Minitest::Assertions

  test "homepage" do
    visit '/'
    screenshot 'homepage'
  end
end
```

### What changes

| Concept | Percy | capybara-screenshot-diff |
|---------|-------|-------------------------|
| Baseline storage | Percy cloud | Committed to git (`doc/screenshots/`) |
| First run | Uploads to Percy | Saves locally, passes automatically |
| CI setup | `PERCY_TOKEN` env var | GitHub Action (3 lines) |
| Diff review | Percy dashboard | `snap_diff_report.html` or PR artifacts |
| Update baselines | Percy's "Approve" button | Delete file, re-run tests, commit |
| Snapshot limits | Paid plan dependent | Unlimited |
| Parallel builds | Built-in | Thread-safe with t-locals + mutex |

### CI migration

**Before (Percy GitHub Action):**
```yaml
- name: Percy Test
  run: PERCY_TOKEN=${{ secrets.PERCY_TOKEN }} bundle exec rake test
```

**After (capybara-screenshot-diff):**
```yaml
- uses: snap-diff/snap_diff-capybara/.github/actions/setup-ruby-and-dependencies@master
  with:
    ruby-version: '4.0'
- run: bundle exec rake test
- uses: snap-diff/snap_diff-capybara/.github/actions/upload-screenshots@master
  if: failure()
  with:
    name: screenshots
    pr-comment: 'true'
```

### Migration steps

1. **Remove Percy gem and configuration**
2. **Add `capybara-screenshot-diff`** to your Gemfile
3. **Replace `Percy::Capybara.screenshot` calls** with `screenshot` (or `match_screenshot` for RSpec)
4. **Run tests once** to generate baselines
5. **Commit baselines** (`git add doc/screenshots/`)
6. **Set up CI** with the GitHub Actions upload step
7. **Remove Percy integration** from CI

---

## From Chromatic

### Setup changes

**Before (Chromatic + Storybook):**
```js
// .storybook/preview.js
import { withScreenshot } from 'chromatic';

export const decorators = [withScreenshot];
```

**After (capybara-screenshot-diff):**
```ruby
# test/system/stories_test.rb
class StoriesTest < ApplicationSystemTestCase
  test "landing page story" do
    visit '/iframe.html?id=pages-landing--default'
    screenshot 'stories/landing-page'
  end
end
```

### Key differences

| Concept | Chromatic | capybara-screenshot-diff |
|---------|-----------|-------------------------|
| Focus | Storybook components | Full-page system tests |
| Baseline | Chromatic cloud | Git-committed |
| Review | Chromatic web UI | HTML report + PR artifacts |
| CI integration | Chromatic GitHub App | GitHub Actions + PR comments |
| Thresholds | Visual catch (AI) | Configurable tolerance (numeric) |

### Migration approach

Chromatic is primarily for Storybook component testing. If you want to continue testing individual components:

1. **Replace with Capybara system tests** that visit each component's rendered page
2. **Use `crop:` option** to isolate specific elements: `screenshot 'button', crop: '.my-button'`
3. **Use `skip_area:` option** to ignore dynamic regions: `screenshot 'dashboard', skip_area: ['.timestamp']`

---

## From BackstopJS

### Setup changes

**Before (BackstopJS):**
```json
// backstop.json
{
  "id": "homepage",
  "viewports": [{"width": 1280, "height": 1024}],
  "scenarios": [{
    "label": "Homepage",
    "url": "http://localhost:3000",
    "referenceUrl": "http://localhost:3000",
    "selectors": ["document"]
  }],
  "paths": {
    "bitmaps_reference": "backstop_data/bitmaps_reference",
    "bitmaps_test": "backstop_data/bitmaps_test",
    "html_report": "backstop_data/html_report"
  }
}
```

**After (capybara-screenshot-diff):**
```ruby
class HomepageTest < ApplicationSystemTestCase
  test "homepage" do
    visit '/'
    screenshot 'homepage'
  end
end
```

### Key differences

| Concept | BackstopJS | capybara-screenshot-diff |
|---------|-----------|-------------------------|
| Language | JavaScript + Node | Ruby (runs in test suite) |
| Dependencies | Node, Puppeteer/Chromium | Ruby gems + optional libvips |
| Test runner | Standalone CLI | Minitest, RSpec, Cucumber |
| Selectors | CSS selectors for scenarios | CSS selectors for crop/skip_area |
| Viewports | Per-scenario config | Global `window_size` setting |
| CI report | HTML report | HTML report + GitHub Actions |
| Stability | `misMatchThreshold` + `delay` | `tolerance` + `stability_time_limit` |

### Configuration mapping

| BackstopJS option | capybara-screenshot-diff equivalent |
|-------------------|-------------------------------------|
| `misMatchThreshold` | `tolerance` (0.0-1.0 scale, e.g. `0.01` = 1%) |
| `delay` | `stability_time_limit` (seconds) |
| `selectors` | `crop:` option with CSS selector |
| `hideSelectors` | `skip_area:` option with CSS selectors |
| `removeSelectors` | N/A — use `skip_area` or modify DOM before screenshot |
| `waitTimeout` | `wait:` option (defaults to `Capybara.default_max_wait_time`) |
| `viewports` | `window_size: [width, height]` |
| `onReadyScript` | Custom setup in your test's `setup` block |

### CI migration

**Before (BackstopJS in CI):**
```yaml
- run: npx backstop test --config=backstop.json
```

**After (capybara-screenshot-diff in CI):**
```yaml
- uses: snap-diff/snap_diff-capybara/.github/actions/setup-ruby-and-dependencies@master
- run: bundle exec rake test
- uses: snap-diff/snap_diff-capybara/.github/actions/upload-screenshots@master
  if: failure()
  with:
    name: screenshots
    pr-comment: 'true'
```

### Migration steps

1. **Remove BackstopJS configuration** (`backstop.json`, npm dependencies)
2. **Convert scenarios to Capybara tests** — each scenario becomes a `screenshot` call
3. **Map threshold and delay settings** to `tolerance` and `stability_time_limit`
4. **Run tests** to generate baselines
5. **Commit baselines** (`git add doc/screenshots/`)
6. **Update CI** to use the GitHub Actions setup

---

## General Migration Checklist

- [ ] Remove old gem/npm dependencies
- [ ] Add `capybara-screenshot-diff` to Gemfile
- [ ] Require the appropriate adapter (`minitest`, `rspec`, or `cucumber`)
- [ ] Replace screenshot calls with `screenshot` / `match_screenshot`
- [ ] Configure `window_size` for consistent viewport dimensions
- [ ] Set `tolerance` or `perceptual_threshold` if your previous tool had a mismatch threshold
- [ ] Add `.gitignore` patterns for diff artifacts
- [ ] Run tests to generate baseline screenshots
- [ ] Commit baselines to git
- [ ] Set up CI with artifact upload
- [ ] Optional: add HTML reporter and PR commenting

## Common Gotchas

### "My baselines are on Percy/Chromatic servers"

You'll need to take fresh screenshots. Either:
- Visit each page and capture manually
- Run tests with `RECORD_SCREENSHOTS=1` to generate all baselines at once

### "I had hundreds of BackstopJS scenarios"

Start small. Migrate one test file at a time. The `screenshot_group` feature helps organize related screenshots:
```ruby
screenshot_group 'checkout'
screenshot 'step1'
screenshot 'step2'
# Produces: doc/screenshots/checkout/00_step1.png, 01_step2.png
```

### "My tests are slow now"

Use the VIPS driver for ~50ms comparisons per image:
```ruby
gem 'ruby-vips'
Capybara::Screenshot::Diff.driver = :vips
```

### "The diffs look different from what I'm used to"

Each tool uses different comparison algorithms:
- **Percy:** Proprietary pixel-level comparison with AI smoothing
- **Chromatic:** Visual catch algorithm (structure-aware)
- **BackstopJS:** Resemble.js pixel comparison
- **capybara-screenshot-diff:** Raw pixel difference with configurable tolerance

Start with default settings, then adjust `tolerance` or `perceptual_threshold` based on your needs.

## Need Help?

- [Architecture Overview](docs/architecture.md) — understanding how comparisons work
- [Configuration Reference](docs/configuration.md) — all available options
- [CI Integration](docs/ci-integration.md) — setting up in CI
- [GitHub Issues](https://github.com/snap-diff/snap_diff-capybara/issues) — ask questions
