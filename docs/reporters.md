# Reporters

## Web UI for Reviewing Screenshot Changes

Generate an interactive Web UI report of screenshot differences:

```ruby
# Add to test_helper.rb — one line, that's it
require 'snap_diff/reporters/html'            # canonical
# require 'capybara_screenshot_diff/reporters/html'   # legacy, same thing
```

After running tests, open the report (generated only when there are failures):

```bash
open doc/screenshots/snap_diff_report.html
```

The report includes a sidebar with thumbnails, side-by-side comparison with diff toggle, search, and summary stats. No configuration needed — just require it.

**Note:** The report is not generated when all screenshots match.

## Parallel test runs

`finalize` — the hook that writes the report — runs from the framework's end-of-suite hook. Whether
that hook fires in the process holding the results depends on how your runner parallelizes:

| How the suite runs | Report |
| --- | --- |
| Serial | Written, complete. |
| `parallelize(with: :threads)` (also the default on JRuby) | Written, complete — same failures and counts as a serial run; only the order of the entries differs. |
| `parallelize(workers: N)` (Rails' default, forks) | **Not written at all** — and the `[snap_diff] N screenshots compared …` summary line is not printed either. |
| One process per worker (`parallel_tests`, RSpec, CI sharding) | Written, but only the **last** process to finish is in it; the others are overwritten. |

Under Rails' forking parallelism the workers hold the results but never finalize: Minitest skips its
`after_run` hooks in a forked child (`Minitest.allow_fork` defaults to `false`), and the parent
process — the one that does finalize — recorded nothing. Test results are unaffected: failures still
fail the suite. Every image artifact is still written too (`*.diff.png`, `*.base.diff.png`,
`*.heatmap.diff.png`), so a failure stays fully debuggable on disk. Only the HTML index is missing.

`ActiveSupport.test_parallelization_threshold` defaults to 50, so a suite of 50 tests or fewer runs
serially and keeps its report. Crossing that threshold is when the report disappears.

### Getting the report back under forked parallelism

Rails runs `parallelize_teardown` hooks *inside* each worker, before it exits. Finalize there, and
give each worker its own output path so workers cannot overwrite each other:

```ruby
# test_helper.rb
require 'snap_diff/reporters/html'

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)

  parallelize_setup do |worker|
    SnapDiff::Reporting.reporters.clear   # drop the auto-registered shared-path reporter
    SnapDiff::Reporting.register(
      SnapDiff::Reporters::HTML.new(output_path: "tmp/snap_diff_report-#{worker}.html")
    )
  end

  parallelize_teardown do |_worker|
    SnapDiff::Reporting.finalize!         # Minitest's after_run hook does not fire in a fork
  end
end
```

That gives one report per worker that had failures — a worker with none writes no file — and no
failure is lost. Alternatively run the suite in a single process with `PARALLEL_WORKERS=1`, which
restores the one complete report.

Do **not** separate workers with a per-worker `save_path`: `save_path` is also where baselines are
read from (`SnapDiff.config.screenshot_area`), so changing it per worker points the comparison at an
empty baseline directory and every screenshot is recorded as new.

See [Thread safety](thread_safety.md) for the state each mode shares.

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
SnapDiff::Reporting.register(MyReporter.new)   # canonical — appends under the mutex
# CapybaraScreenshotDiff.reporters << MyReporter.new   # legacy, same list, skips the lock
```

Reporters are notified before assertions are cleared on each test teardown. `finalize` runs from
the framework's end-of-suite hook (`Minitest.after_run`, RSpec `after(:suite)`, Cucumber
`AfterAll`), which calls `SnapDiff::Reporting.finalize!`.

**Do implement `summary`.** `finalize!` calls it unconditionally, so a reporter without it is
finalized and then warned about. A reporter that raises is warned about and skipped — the others
still run.

Full details in [Custom reporters](snapdiff.md#custom-reporters).

[← Back to README](../README.md)
