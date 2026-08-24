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

## The end-of-run summary

Every run ends with what it actually did, whether or not you require a reporter:

```
[snap_diff] 12 verified, 1 changed, 2 new (not verified).
```

- **verified** — a committed baseline existed and was compared
- **changed** — of those, the ones that differed
- **new** — captured but *not* compared, for want of a committed baseline: neither a pass nor a
  failure. Commit the files to turn them into baselines.

`0 verified` is printed as `NOTHING WAS VERIFIED`, because it is the only signal for the failures
no per-assertion rule can see: a `rake test` that ran zero system tests, or an inherited `GIT_DIR`
sending every baseline lookup to the wrong repository. Both leave a green suite that compared
nothing.

Requiring `snap_diff/reporters/html` adds one more line, naming the file it wrote:

```
[snap_diff] Report: doc/screenshots/snap_diff_report.html
```

## Parallel test runs

`finalize` — the hook that writes the report — runs from the framework's end-of-suite hook. Whether
that hook fires in the process holding the results depends on how your runner parallelizes:

| How the suite runs | Report |
| --- | --- |
| Serial | Written, complete. |
| `parallelize(with: :threads)` (also the default on JRuby) | Written, complete — same failures and counts as a serial run; only the order of the entries differs. Verified over repeated runs, provided [screenshot names are unique across tests](thread_safety.md#screenshot-names-must-be-unique-across-tests). |
| `parallelize(workers: N)` (Rails' default, forks) | Written, complete — one report at the usual path, merged from every worker. No configuration needed. |
| One process per worker (`parallel_tests`, RSpec, CI sharding) | Written, but only the **last** process to finish is in it; the others are overwritten. |

Under Rails' forking parallelism the workers hold the results but never finalize: Minitest skips its
`after_run` hooks in a forked child (`Minitest.allow_fork` defaults to `false`), and the parent
process — the one that does finalize — recorded nothing. So each worker now hands its records to the
parent on the way out (Rails' `run_cleanup` hook runs *inside* the worker), and the parent merges
them before it writes the report. `N verified, N changed, N new` are the merged totals for the whole
suite, not one worker's.

The handoff goes through a scratch directory under the system temp dir, removed as soon as the merge
is done. Nothing is written inside your repository, and a worker killed mid-write leaves nothing the
merge will read.

### Rails versions and older workarounds

The merge uses `ActiveSupport::Testing::Parallelization`'s worker hooks and is registered only when
Rails is present, so a non-Rails Capybara suite is unaffected.

If your `test_helper.rb` still carries the old per-worker workaround —

```ruby
parallelize_teardown { SnapDiff::Reporting.finalize! }   # no longer needed
```

— you can delete it. Left in place it does not corrupt anything: the merged report is written last,
at the documented path, with every failure in it. It just adds noise — each worker writes its own
partial report over the same file first, and prints its own partial summary line (`32 verified …`
four times, then the real one).

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
