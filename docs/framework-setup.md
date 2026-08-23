# Framework Setup

Minitest, RSpec and Cucumber are supported out of the box. Each is one require plus, in some
cases, one include.

> The require path is `snap_diff/integrations/…`, not `snap_diff/…` —
> `require "snap_diff/minitest"` raises `LoadError`.

## Minitest

Require `snap_diff/integrations/minitest`, then include `SnapDiff::Minitest::Assertions` in your
test class. It brings `SnapDiff::DSL` with it, so a separate `include SnapDiff::DSL` is not
needed.

```ruby
require 'snap_diff/integrations/minitest'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # `screenshot` / `assert_matches_screenshot`, wired to Minitest's assertion counter
  include SnapDiff::Minitest::Assertions

  def test_my_feature
    visit '/'
    assert_matches_screenshot 'index'
  end
end
```

## RSpec

Requiring `snap_diff/integrations/rspec` registers the `match_screenshot` matcher and includes
`SnapDiff::DSL` into `type: :feature` and `type: :system` examples automatically.

```ruby
require 'snap_diff/integrations/rspec'

describe 'Permissions admin', type: :feature do
  it 'works with permissions' do
    visit('/')
    expect(page).to match_screenshot('home_page')
  end
end
```

For other example types, include the DSL yourself:

```ruby
describe 'Permissions admin', type: :non_feature do
  include SnapDiff::DSL

  it 'works with permissions' do
    visit('/')
    expect(page).to match_screenshot('home_page')
  end
end
```

## Cucumber

Load Cucumber support by adding the following line (typically to your `features/support/env.rb`
file):

```ruby
require 'snap_diff/integrations/cucumber'
```

The DSL is added to the Cucumber `World`, so steps can call it directly:

```ruby
Then('I should not see any visual difference') do
  screenshot 'homepage'
end
```

This file must be loaded from inside a Cucumber run — it calls `World`, `Before`, `After` and
`AfterAll` at load time and raises `NoMethodError` if required outside one.

## Custom Test Frameworks

For other frameworks, call the end-of-suite hook yourself:

```ruby
SnapDiff::Reporting.finalize!
```

This generates the HTML report and prints the summary. A framework also needs the per-test
lifecycle wired up — see
[Frameworks other than Minitest/RSpec/Cucumber](snapdiff.md#frameworks-other-than-minitestrspeccucumber).

[← Back to README](../README.md)
