# Framework Setup

## Including DSL

To use the screenshot capturing and change detection features in your tests, include the `CapybaraScreenshotDiff::DSL` in your test classes. It provides the `screenshot` method to capture and compare screenshots.

There are different modules for different testing frameworks integrations.

## Minitest

For Minitest, need to require `capybara_screenshot_diff/minitest`.
In your test class, include the `CapybaraScreenshotDiff::Minitest::Assertions` module:

```ruby
require 'capybara_screenshot_diff/minitest'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Make the Capybara & Capybara Screenshot Diff DSLs available in tests
  include CapybaraScreenshotDiff::DSL
  # Make `assert_*` methods behave like Minitest assertions
  include CapybaraScreenshotDiff::Minitest::Assertions

  def test_my_feature
    visit '/'
    assert_matches_screenshot 'index'
  end
end
```

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

Minitest, RSpec, and Cucumber are supported out of the box. For other frameworks, call `finalize_reporters!` in your framework's "after suite" hook:

```ruby
CapybaraScreenshotDiff.finalize_reporters!
```

This generates the HTML report and prints the summary.

[← Back to README](../README.md)
