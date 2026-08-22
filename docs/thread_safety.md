# Thread Safety Guide for Parallel Testing

This document explains how `snap_diff` behaves under Rails parallel tests with the `:thread` strategy.

## Overview

`snap_diff` is thread safe for parallel test execution as long as global configuration is set before tests run. Per-thread state is isolated, and shared state is protected where it matters.

## Architecture Summary

### Per-thread Assertion Registry

Each thread gets its own `AssertionRegistry` stored in thread-local storage:

```ruby
def registry
  Thread.current[:capybara_screenshot_diff_registry] ||= AssertionRegistry.new
end
```

This prevents cross-thread leakage for assertions and screenshot naming.

### Reporters Snapshot on Notify

Reporters are notified using a snapshot protected by an eagerly initialized mutex:

```ruby
@reporters_mutex = Mutex.new

def notify_reporters(assertions)
  reporters_snapshot = reporters_mutex.synchronize { reporters.dup }
  reporters_snapshot.each { |reporter| reporter.record(assertions) }
end
```

This ensures a stable list while notifying without forcing a global lock around reporter work.

### HTML Reporter Internal Lock

The HTML reporter protects `@failures`, `@total`, and `@finalized` with a mutex so `record` and `finalize` can run safely:

```ruby
@mutex.synchronize do
  return if @finalized
  @total += total
  @failures.concat(failures)
end
```

`@finalized` is set only after `write_report` succeeds, so a failed write can be retried.

### Screenshot Naming Isolation

Each thread gets its own `ScreenshotNamer` via the per-thread registry, so counters, sections, and groups do not collide.

### SnapManager Per Call

`SnapManager` returns a new instance for each call, avoiding shared mutable state.

## Global Configuration

Configuration uses `mattr_accessor` and should be set once before tests run. Do not mutate config during parallel execution.

## Parallel Test Lifecycle

- Setup: per-thread registry is created, config is read
- Execution: assertions are added to the thread-local registry
- Teardown: `verify` and `reset` operate on the thread-local registry, reporters are notified
- Exit: reporters finalize once per process (using mutex-protected snapshot)

## Usage Examples

```ruby
parallelize(workers: :number_of_processors, with: :threads)

Capybara::Screenshot::Diff.configure do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
  screenshot.save_path = "doc/screenshots"
  diff.tolerance = 0.001
end
```

## Do and Do Not

Do:
- Set config once in test helper
- Pass per-screenshot options in the call

Do not:
- Change global config inside tests
- Manually mutate registry internals

## File System Notes

- Paths are unique per screenshot name and counter
- `FileUtils.mv` is atomic on most file systems
- Directory creation uses `mkpath`

## Load-time thread safety

Runtime state is thread-local (above), but *loading* the gem is a separate
concern. The require graph is deliberately acyclic: `lib/snap_diff/*` units
depend only on the legacy-config leaf
(`capybara/screenshot/diff/config_legacy`) and specific sibling units, the
umbrella files depend on the units, and nothing requires back up the chain.

Eager mutual requires between entry points are forbidden, even guarded ones:
per-thread "loading" flags cannot serialize Ruby's process-global per-file
require locks, so two threads requiring opposite entry points first can
deadlock (lock-order inversion — observed deterministically before this
design). If two files ever need each other, extract the shared piece into a
leaf both can require instead.
