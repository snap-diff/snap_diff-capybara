# Parallel and Thread Safety Guide

How `snap_diff` behaves when your test suite runs tests concurrently — Rails
`parallelize`, `parallel_tests`, or CI sharding.

## Summary

| How the suite runs | Assertions and results | HTML report |
| --- | --- | --- |
| Serial | Correct | Written, complete |
| `parallelize(with: :threads)` — also the default on JRuby | **Correct — fully supported** | Written, complete |
| `parallelize(workers: N)` — Rails' default, forks | Correct | Not written ([why, and how to get it back](reporters.md#parallel-test-runs)) |
| One process per worker (`parallel_tests`, RSpec, CI sharding) | Correct | Written, but only the last process to finish is in it |

Two rules make all of these safe:

1. **Set configuration once, before tests run.** There is one `SnapDiff::Config`
   per process and nothing guards it.
2. **Give every screenshot a name no other test uses.** See
   [Screenshot names must be unique](#screenshot-names-must-be-unique-across-tests)
   — this one is not cosmetic.

## What is shared, and what protects it

| State | Scope | Protection |
| --- | --- | --- |
| `SnapDiff.config` — every setting | One instance per process | None. Set it before tests start; do not mutate it during the run |
| `SnapDiff.session` — the assertion registry, the new-screenshot list, and the `ScreenshotNamer` (section, group, counter) | Per fiber (`Thread.current[]` is fiber-local) | Isolation — threads never share one |
| `SnapDiff::SnapManager.instance` and its tracked-snapshot set | Per fiber, memoized; rebuilt when the manager class or screenshot root changes | Isolation |
| `SnapDiff::Reporting.reporters` | One list per process | A mutex: `register` appends under it, `notify`/`finalize!` iterate a snapshot taken under it |
| `SnapDiff::Reporters::HTML` totals and failures | One reporter per process | Its own mutex around `record` and `finalize` |
| Deprecation "warn once" memos | Per process | A mutex. Note "once per process" means once *per fork worker* — expect N copies under forking parallelism |
| `SnapDiff::Vcs` repository-root memo | One hash per process | None. Values are idempotent (same directory, same answer), so a lost write costs one extra `git rev-parse`, but a plain Hash is not a concurrent container on JRuby or TruffleRuby |
| Screenshot files: `<name>.png`, `<name>.base.png`, `<name>.attempt_NN.png`, `<name>.diff.png`, … | On disk, shared by every thread and every process | **None — the paths derive from the screenshot name alone** |

## Screenshot names must be unique across tests

Every artifact path is built from the screenshot name and nothing else — not the
test name, not the worker, not the thread. Two tests using the same name share
every file involved in the comparison.

Serially that is merely wasteful: the tests overwrite each other in order. In
parallel it is dangerous. When two concurrently running tests share a name, one
test's post-pass baseline archiving moves the baseline that the other just
checked out, and the second test then finds no baseline — so it records the
screenshot as *new* and **returns without comparing anything**. The test passes
green having verified nothing. A run of 64 concurrent assertions sharing 8 names
measured between 18 and 34 comparisons silently skipped this way, alongside a
scatter of loud errors from the same collisions (truncated PNG reads, `mv`
failures).

Use `screenshot_section` / `screenshot_group`, or name screenshots after the test,
so no two tests can collide.

## Configuration

Configure once, in `test_helper.rb` / `spec_helper.rb`, before any test runs:

```ruby
SnapDiff.configure do |config|
  config.window_size = [1280, 1024]
  config.save_path = "doc/screenshots"
  config.tolerance = 0.001
end
```

Pass anything that varies per screenshot as an argument instead
(`assert_matches_screenshot("name", tolerance: 0.02)`) rather than reassigning
config mid-run: one process's config is shared by all of its threads, so a test
that mutates it changes what every concurrently running test sees.

## Test lifecycle

- **Setup** — the fiber-local session is created on first use.
- **Execution** — assertions accumulate in the fiber's own registry.
- **Teardown** — `verify` and `reset` act on that fiber's registry, then hand its
  assertions to the process's reporters.
- **End of suite** — reporters finalize once per process, from the framework's
  end-of-suite hook (`Minitest.after_run`, RSpec `after(:suite)`, Cucumber
  `AfterAll`). Forked workers are the exception: see
  [Parallel test runs](reporters.md#parallel-test-runs).

## Load-time thread safety

Runtime state is thread-local (above), but *loading* the gem is a separate
concern. The require graph is deliberately acyclic: `lib/snap_diff/*` units
depend only on the config-storage leaf (`snap_diff/config`, which the legacy
view `capybara/screenshot/diff/config_legacy` requires) and specific sibling
units, the umbrella files depend on the units, and nothing requires back up
the chain.

Eager mutual requires between entry points are forbidden, even guarded ones:
per-thread "loading" flags cannot serialize Ruby's process-global per-file
require locks, so two threads requiring opposite entry points first can
deadlock (lock-order inversion — observed deterministically before this
design). If two files ever need each other, extract the shared piece into a
leaf both can require instead.
