# Framework Setup

> **Canonical equivalents.** This page uses the legacy `CapybaraScreenshotDiff` names, which keep
> working. Each has a `SnapDiff` home:
>
> | This page | Canonical |
> |-----------|-----------|
> | `require "capybara_screenshot_diff/minitest"` | `require "snap_diff/integrations/minitest"` |
> | `require "capybara_screenshot_diff/rspec"` | `require "snap_diff/integrations/rspec"` |
> | `require "capybara_screenshot_diff/cucumber"` | `require "snap_diff/integrations/cucumber"` |
> | `CapybaraScreenshotDiff::DSL` | `SnapDiff::DSL` |
> | `CapybaraScreenshotDiff::Minitest::Assertions` | `SnapDiff::Minitest::Assertions` |
> | `CapybaraScreenshotDiff.finalize_reporters!` | `SnapDiff::Reporting.finalize!` |
>
> The canonical setup, written out in full, is in [SnapDiff — the canonical API](snapdiff.md).

## Including DSL

To use the screenshot capturing and change detection features in your tests, include the `CapybaraScreenshotDiff::DSL` in your test classes. It provides the `screenshot` method to capture and compare screenshots.

There are different modules for different testing frameworks integrations.

## Minitest

For Minitest, need to require `capybara_screenshot_diff/minitest`.
In your test class, include the `CapybaraScreenshotDiff::Minitest::Assertions` module:

```ruby
# test/application_system_test_case.rb
require 'test_helper'
require 'capybara_screenshot_diff/minitest'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Pin the browser: window size and pixel ratio are inputs to every comparison
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  # Make `assert_*` methods behave like Minitest assertions.
  # This already includes CapybaraScreenshotDiff::DSL — a separate include is not needed.
  include CapybaraScreenshotDiff::Minitest::Assertions

  def test_my_feature
    visit '/'
    assert_matches_screenshot 'index'
  end
end
```

Run it with `bin/rails test:system` — `rake test` / `rails test` skip `test/system/` and
report `0 runs`.

## RSpec

To use the screenshot capturing and change detection features in your tests,
include the `CapybaraScreenshotDiff::DSL` in your test classes.
It adds `match_screenshot` matcher to RSpec.

> **Important**:
> The `CapybaraScreenshotDiff::DSL` is automatically included in all feature and system tests by default.


```ruby
require 'capybara_screenshot_diff/rspec'

describe 'Permissions admin', type: :feature do
  it 'works with permissions' do
    visit('/')
    expect(page).to match_screenshot('home_page')
  end
end


describe 'Permissions admin', type: :non_feature do
  include CapybaraScreenshotDiff::DSL

  it 'works with permissions' do
    visit('/')
    expect(page).to match_screenshot('home_page')
  end
end
```

## Cucumber

Load Cucumber support by adding the following line (typically to your `features/support/env.rb` file):

```ruby
require 'capybara_screenshot_diff/cucumber'
```

And in the steps you can use:

```ruby
Then('I should not see any visual difference') do
  screenshot 'homepage'
end
```

## Custom Test Frameworks

Minitest, RSpec, and Cucumber are supported out of the box. For other frameworks, call the
end-of-suite hook yourself:

```ruby
SnapDiff::Reporting.finalize!            # canonical
CapybaraScreenshotDiff.finalize_reporters!   # legacy, same thing
```

This generates the HTML report and prints the summary. A framework also needs the per-test
lifecycle wired up — see
[Frameworks other than Minitest/RSpec/Cucumber](snapdiff.md#frameworks-other-than-minitestrspeccucumber).

[← Back to README](../README.md)
