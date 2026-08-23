# Docker Testing

## Running tests in Docker

Screenshot tests depend on exact browser rendering, which varies across OS and browser versions. Use `bin/dtest` to run tests inside Docker for consistent, reproducible results matching CI:

```bash
bin/dtest                          # Run all tests against every Capybara driver
bin/dtest test/integration/        # Run specific test directory
```

This builds a Docker image with Chrome and runs the test suite against three Capybara drivers: `cuprite`, `selenium_chrome_headless`, and `selenium_headless`.

## Recording baseline screenshots

Screenshot baselines are committed to the repo and compared against during tests. When you set up the project for the first time, or after upgrading the browser/driver, you need to re-record them:

```bash
RECORD_SCREENSHOTS=1 bin/dtest
```

This skips screenshot comparisons and saves new baselines instead. Without this step, tests will fail because your local browser renders pixels differently from the previously committed baselines.

[← Back to README](../README.md)
