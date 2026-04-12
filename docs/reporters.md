# Reporters

## Web UI for Reviewing Screenshot Changes

Generate an interactive Web UI report of screenshot differences:

```ruby
# Add to test_helper.rb — one line, that's it
require 'capybara_screenshot_diff/reporters/html'
```

After running tests, open the report (generated only when there are failures):

```bash
open doc/screenshots/snap_diff_report.html
```

The report includes a sidebar with thumbnails, side-by-side comparison with diff toggle, search, and summary stats. No configuration needed — just require it.

**Note:** The report is not generated when all screenshots match. In parallel test environments, each worker writes to the same file — the last worker's results will be in the report.

## Custom Reporters

Build your own reporter by implementing `record` and `finalize`:

```ruby
class MyReporter
  def record(assertions)
    assertions.each do |assertion|
      next unless assertion.compare&.difference&.different?
      # process the failure — send to Slack, write JSON, etc.
    end
  end

  def finalize
    # called once at process exit — write summary, upload report, etc.
  end
end

# Register in test_helper.rb
CapybaraScreenshotDiff.reporters << MyReporter.new
```

Reporters are notified before assertions are cleared on each test teardown. `finalize` is called via `at_exit`.

[← Back to README](../README.md)
