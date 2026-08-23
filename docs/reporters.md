# Reporters

## Web UI for Reviewing Screenshot Changes

Generate an interactive Web UI report of screenshot differences:

```ruby
# Add to test_helper.rb — one line, that's it
require 'snap_diff/reporters/html'
```

After running tests, open the report (generated only when there are failures):

```bash
open doc/screenshots/snap_diff_report.html
```

The report includes a sidebar with thumbnails, side-by-side comparison with diff toggle, search, and summary stats. No configuration needed — just require it.

**Note:** The report is not generated when all screenshots match. In parallel test environments, each worker writes to the same file — the last worker's results will be in the report.

## Custom Reporters

Build your own reporter by implementing `record`, `finalize` and `summary`:

```ruby
class MyReporter
  def record(assertions)
    assertions.each do |assertion|
      next unless assertion.compare&.difference&.different?
      # process the failure — send to Slack, write JSON, etc.
    end
  end

  def finalize
    # called once at end of suite — write summary, upload report, etc.
  end

  def summary
    # printed to stdout after finalize; return nil to print nothing
    nil
  end
end

# Register in test_helper.rb
SnapDiff::Reporting.register(MyReporter.new)   # appends under the mutex
```

Reporters are notified before assertions are cleared on each test teardown. `finalize` runs from
the framework's end-of-suite hook (`Minitest.after_run`, RSpec `after(:suite)`, Cucumber
`AfterAll`), which calls `SnapDiff::Reporting.finalize!`.

**Do implement `summary`.** `finalize!` calls it unconditionally, so a reporter without it is
finalized and then warned about. A reporter that raises is warned about and skipped — the others
still run.

Full details in [Custom reporters](snapdiff.md#custom-reporters).

[← Back to README](../README.md)
