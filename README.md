[![Gem Version](https://badge.fury.io/rb/capybara-screenshot-diff.svg)](https://rubygems.org/gems/capybara-screenshot-diff)
[![Gem Downloads](https://img.shields.io/gem/dt/capybara-screenshot-diff.svg)](https://rubygems.org/gems/capybara-screenshot-diff)
[![Test](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/test.yml/badge.svg)](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/test.yml)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-snap--diff%2Fsnap__diff--capybara-blue.svg?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggZD0iTTEyIDJhMTAgMTAgMCAxIDAgMCAyMCAxMCAxMCAwIDAgMCAwLTIweiIvPjxwYXRoIGQ9Ik0xMiA2djEyIi8+PHBhdGggZD0iTTYgMTJoMTIiLz48L3N2Zz4=)](https://deepwiki.com/snap-diff/snap_diff-capybara)

# Capybara::Screenshot::Diff

Stop shipping UI bugs. Take screenshots in your Capybara tests, commit baselines to git, and let CI catch visual regressions in pull requests — no cloud service, no subscription, runs entirely in your test suite.

[![SnapDiff Web UI](docs/images/snap_diff_web_ui.png)](#web-ui-for-reviewing-screenshot-changes)

**Why this gem?** Baselines live in git — review UI changes in pull requests like you review code. Runs offline, works in CI, zero vendor lock-in. Unlike Percy/Chromatic (paid SaaS), nothing to sign up for. Unlike BackstopJS, no Node required.

> **2.0 is the transitional release.** The gem's canonical namespace is now `SnapDiff`. Upgrading from 1.x is a version bump — every legacy `Capybara::Screenshot::Diff` / `CapybaraScreenshotDiff` name still resolves to the same object and keeps working. The first legacy API a process touches prints one migration notice (lazily shimmed constants also warn once each — see [which names warn](docs/UPGRADING.md#deprecation-warnings)), silenceable via `SnapDiff.silence_deprecations = true` or `SNAP_DIFF_SILENCE_DEPRECATIONS=1`.
>
> **2.1 removes what 2.0 warns about**: the legacy namespaces, the ChunkyPNG driver, `shift_distance_limit`, the `driver:` setting and the driver abstraction — libvips becomes the only backend. There is no 3.0. Writing new code? Start from [SnapDiff — the canonical API](docs/snapdiff.md), which uses canonical names only. Migrating an existing suite? See the [upgrade guide](docs/UPGRADING.md).
>
> **Two gem names, one gem — install `capybara-screenshot-diff`.** From 2.0.0 on, the identical content is also published as [`snap_diff-capybara`](https://rubygems.org/gems/snap_diff-capybara), the forward-looking name matching this repository. Do not reach for it yet: that name's only non-prerelease before 2.0.0 is a `0.0.1` placeholder containing a README and no Ruby files, so an unpinned `gem "snap_diff-capybara"` installs an empty gem and fails with `LoadError`. **Always pin the version**, and **install one name, never both** — with both in a Gemfile the gem raises `SnapDiff::DualInstallError` at require time.

## Quick Start (5 minutes)

> Already using Capybara for system tests? Add the gem and you're ready. New to system tests? See [Rails System Testing guide](https://guides.rubyonrails.org/testing.html#system-testing).

```ruby
# Gemfile
gem 'capybara-screenshot-diff', '~> 2.0'   # pin: unpinned resolves to the 1.x line
gem 'ruby-vips'                            # The image backend. Needs libvips — see Installation below
```

The gem ships no image backend of its own. Add `ruby-vips` (recommended, and the only
backend from 2.1 on) or `chunky_png` (pure Ruby, no system library, removed in 2.1) — with
neither, comparisons raise `Wrong adapter nil. Available adapters: []`.

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
    assert_matches_screenshot "homepage"
  end
end
```

(`screenshot` still works as a shorthand, and is safe to override in your own helpers — the gem no longer calls it internally.)

Then run these steps in order:

```bash
# Step 1: Save baselines (first run always passes)
bundle exec rake test

# Step 2: Commit baselines to git
git add doc/screenshots/
git commit -m "chore: add screenshot baselines"

# Step 3: Now comparisons work — change your UI and re-run
bundle exec rake test
```

After Step 1, you'll see:
```text
doc/screenshots/
  homepage.png          <- your baseline (commit this)
```

Add diff artifacts to `.gitignore` — these are generated at runtime and should not be committed:
```gitignore
# Screenshot diff artifacts (generated, not committed)
*.diff.png
*.base.png
*.diff.webp
*.base.webp
snap_diff_report.html
```

If you skip Step 2 and push to CI, the build will fail — `fail_if_new` is `true` by default in CI.

For RSpec, Cucumber, or non-Rails setup, see [Framework Setup](docs/framework-setup.md).

### For Non-Rails Projects (Hugo, Jekyll, Static Sites)

```ruby
require 'capybara_screenshot_diff/static'
CapybaraScreenshotDiff.serve("_site")  # or "public", "build", "dist"
```

Then commit baselines to git just like Rails. [Full setup](docs/ci-integration.md#non-rails-projects-hugo-jekyll-static-sites).

## What Happens When a Screenshot Changes

The test fails with a clear message and generates diff files:

```text
Screenshot does not match for 'homepage':
({"area_size":1250,"region":[0,19,199,83],"max_color_distance":42.5})
```

Open `doc/screenshots/homepage.diff.png` to see exactly what changed. If the change is intentional, see [Accepting an intentional change](#accepting-an-intentional-change).

| File | Description |
|------|-------------|
| `homepage.png` | Committed baseline |
| `homepage.diff.png` | Visual diff with changes highlighted in red |
| `homepage.heatmap.diff.png` | Heatmap of pixel differences |

## Accepting an intentional change

**Baselines are read from git, not from your working directory.** Every comparison runs
`git show HEAD:<path>` for the baseline, so a screenshot that is committed is the one you
are compared against — no matter what the file on disk says.

That makes the obvious move the wrong one: **deleting the baseline file does nothing.** The
gem fetches the committed copy from `HEAD` and the test fails exactly as before.

Accepting a change is therefore a **commit**, not a file operation. The run writes its new
capture to the baseline path, so `git status` shows the baseline as modified — review it and
commit it:

```bash
git status                     # doc/screenshots/homepage.png is modified
git diff --stat doc/screenshots/

# Look at homepage.diff.png. If the change is what you wanted:
git add doc/screenshots/homepage.png
git commit -m "chore: update homepage baseline"

bundle exec rake test          # now green — HEAD holds the new baseline
```

> **Staging is not enough.** `git add` alone does not move `HEAD`, so a staged-but-uncommitted
> baseline is still compared against the old committed one. You cannot get a green local run
> until you commit. That is by design: the baseline under review in a pull request is exactly
> the baseline the suite uses.

Reviewing the change is what the pull request is for — the updated `.png` shows up as an image
diff next to the code that caused it.

## Web UI for Reviewing Screenshot Changes

Add one line to get an interactive dashboard for reviewing all screenshot differences:

```ruby
# test/test_helper.rb
require 'capybara_screenshot_diff/reporters/html'
```

After tests run, open `doc/screenshots/snap_diff_report.html`:

![SnapDiff Web UI — annotated diff showing changed regions highlighted in red](docs/images/snap_diff_annotated.png)

See [Web UI & Custom Reporters](docs/reporters.md) for full feature details and [CI Integration](docs/ci-integration.md) for GitHub Actions setup.

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
  screenshot.window_size = [1280, 1024]        # consistent viewport
  diff.perceptual_threshold = 2.0              # ignore anti-aliasing (VIPS only)
  # or: diff.tolerance = 0.001                 # percentage-based (default for VIPS)
end
```

See [Choosing the Right Method](docs/configuration.md#choosing-the-right-color-comparison-method) for detailed comparison options.

## FAQ

<details>
<summary><strong>The test passed on first run. Did it work?</strong></summary>

Yes. First run saves baselines and always passes. Run tests again to compare against committed baselines.
</details>

<details>
<summary><strong>How do I update baselines after intentional UI changes?</strong></summary>

**Not by deleting the file** — baselines are read from git (`git show HEAD:<path>`), so `rm` has no effect on what you are compared against. Commit the new capture instead: `git add doc/screenshots/homepage.png && git commit`. See [Accepting an intentional change](#accepting-an-intentional-change).
</details>

<details>
<summary><strong>CSS animations make my screenshots flaky</strong></summary>

Enable `Capybara::Screenshot.disable_animations = true` to freeze CSS animations/transitions before each capture. Or use `stability_time_limit: 1` to wait for animations to finish.
</details>

<details>
<summary><strong>CI screenshots differ from local</strong></summary>

Set `window_size` for consistent dimensions and use `perceptual_threshold: 2.0` to ignore anti-aliasing differences across environments.
</details>

<details>
<summary><strong>Will this slow down my tests?</strong></summary>

Comparisons add ~50ms per image with VIPS. If you add `chunky_png` to your Gemfile instead, it is used as a pure-Ruby fallback (slower, no system dependency, and removed in 2.1). `stability_time_limit` adds wait time — keep it low (0.1-0.5s) or use `disable_animations` instead.
</details>

<details>
<summary><strong>Debug mode</strong></summary>

`DEBUG=1 bundle exec rake test` keeps `.diff.png` files for inspection.
</details>

## Installation

**Requirements:** Ruby 3.2+, Capybara 2–3. Rails 7.1+ for Rails integration; non-Rails projects supported via `CapybaraScreenshotDiff.serve()`. For the `:vips` driver (recommended, and the only backend from 2.1 on): [libvips 8.9+](https://libvips.github.io/libvips/install.html). On macOS: `brew install vips`. On Ubuntu: `apt-get install libvips-dev`.

## Docs

- [SnapDiff — the canonical API](docs/snapdiff.md) — setup, config, object map, custom drivers & reporters, canonical names only
- [Upgrading](docs/UPGRADING.md) — 1.x → 2.0, every renamed constant, which names warn, what 2.1 removes, rollback
- [Framework Setup](docs/framework-setup.md) — Minitest, RSpec, Cucumber
- [CI & Non-Rails Integration](docs/ci-integration.md) — GitHub Actions, reusable action, static sites, baseline updates
- [Configuration Reference](docs/configuration.md) — all options explained
- [Image Processing Drivers](docs/drivers.md) — VIPS, ChunkyPNG, perceptual threshold
- [Screenshot Organization](docs/organization.md) — groups, sections, cropping, multi-browser
- [Web UI & Custom Reporters](docs/reporters.md) — interactive report, custom reporters

## Development

After checking out the repo, run `bin/setup` then `rake test`. See [Docker Testing](https://github.com/snap-diff/snap_diff-capybara/blob/master/docs/docker-testing.md) for reproducible CI-matching test runs.

## Contributing

See [CONTRIBUTING.md](https://github.com/snap-diff/snap_diff-capybara/blob/master/CONTRIBUTING.md)

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
