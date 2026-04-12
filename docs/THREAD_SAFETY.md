# thread safety guide for parallel testing

this document explains how `snap_diff` behaves under rails parallel tests with the `:thread` strategy.

## overview

`snap_diff` is thread safe for parallel test execution as long as global configuration is set before tests run. per thread state is isolated, and shared state is protected where it matters.

## architecture summary

### per-thread assertion registry

each thread gets its own `assertionregistry` stored in thread-local storage:

```ruby
def registry
  thread.current[:capybara_screenshot_diff_registry] ||= assertionregistry.new
end
```

this prevents cross-thread leakage for assertions and screenshot naming.

### reporters snapshot on notify

reporters are notified using a snapshot protected by a mutex:

```ruby
def notify_reporters(assertions)
  reporters_snapshot = reporters_mutex.synchronize { reporters.dup }
  reporters_snapshot.each { |reporter| reporter.record(assertions) }
end
```

this ensures a stable list while notifying without forcing a global lock around reporter work.

### html reporter internal lock

the html reporter protects `@failures`, `@total`, and `@finalized` with a mutex so record and finalize can run safely:

```ruby
@mutex.synchronize do
  return if @finalized
  @total += total
  @failures.concat(failures)
end
```

### screenshot naming isolation

each thread gets its own `screenshotnamer` via the per-thread registry, so counters, sections, and groups do not collide.

### snapshot manager per call

`snapmanager.instance` returns a new instance for each call, avoiding shared mutable state.

## global configuration

configuration uses `mattr_accessor` and should be set once before tests run. do not mutate config during parallel execution.

## parallel test lifecycle

- setup: per-thread registry is created, config is read
- execution: assertions are added to the thread-local registry
- teardown: verify and reset operate on the thread-local registry, reporters are notified
- exit: reporters finalize once per process

## usage examples

```ruby
parallelize(workers: :number_of_processors, with: :threads)

capybara::screenshot::diff.configure do |screenshot, diff|
  screenshot.window_size = [1280, 1024]
  screenshot.save_path = "doc/screenshots"
  diff.tolerance = 0.001
end
```

## do and do not

do:
- set config once in test helper
- pass per-screenshot options in the call

do not:
- change global config inside tests
- manually mutate registry internals

## file system notes

- paths are unique per screenshot name and counter
- `fileutils.mv` is atomic on most file systems
- directory creation uses `mkpath`
