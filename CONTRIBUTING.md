# Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/snap-diff/snap_diff-capybara.
This project is intended to be a safe, welcoming space for collaboration, and contributors are expected
to adhere to the [Contributor Covenant](CODE_OF_CONDUCT.md) code of conduct.

## Development Setup

### Prerequisites

- **Ruby 3.2+** (the project tests against 3.2–4.0)
- **libvips 8.9+** (optional, for the VIPS driver). Install with:
  - macOS: `brew install vips`
  - Ubuntu: `sudo apt-get install libvips-dev`
- **Chrome** (for integration tests with `selenium_chrome_headless` or `cuprite`)

### First-time setup

```bash
bin/setup
```

This installs gem dependencies and prepares the development environment.

### Running tests

```bash
# All tests
rake test

# Unit tests only (faster, no browser required)
rake test:unit

# Integration tests (require a browser)
rake test:integration

# Run specific test file
ruby -Ilib:test test/unit/image_compare_test.rb

# Run with a specific screenshot driver
SCREENSHOT_DRIVER=vips rake test

# Run with a specific Capybara driver (integration tests)
CAPYBARA_DRIVER=cuprite rake test:integration

# Record new baseline screenshots (integration tests)
RECORD_SCREENSHOTS=1 bin/dtest
```

### Docker testing

Use Docker for reproducible CI-matching test runs:

```bash
bin/dtest                     # Run all tests in Docker
bin/dtest test/integration/   # Run specific directory
```

See [docs/docker-testing.md](docs/docker-testing.md) for details.

### Linting

```bash
# Ruby linting (Standard Ruby)
bundle exec standardrb

# Auto-fix
bundle exec standardrb --fix
```

## CI: a green PR does not always mean a green master

**The full `Test Ruby & Rails` matrix does not run on every PR.** It is off by
default to stay inside free-tier Actions minutes, which means the job that breaks
`master` can be a job that never ran on your PR.

It runs automatically when:

- the PR touches **`test/`, `gemfiles/` or `.github/`** — the three paths every
  recent master breakage came from;
- you add the **`full-ci`** label;
- or the push is to `master`, a manual dispatch, or the weekly drift check.

**Add `full-ci` by hand** if your PR could behave differently across Ruby or
Rails versions and does not touch those paths — anything version-conditional
(`defined?`, `respond_to?`, `RUBY_VERSION`), anything touching subprocess or
environment handling, or anything you would be surprised to see break on JRuby.
`lib/` is deliberately **not** on the automatic list: it changes on nearly every
PR, and the functional and minimal-setup jobs already cover it. That trade is a
cost decision, not a claim that `lib/` is safe.

Two things about reading CI results here:

- **`cancelled` is not a pass.** It means a later push superseded the run, or
  fail-fast killed the cell before it reported. It occupies the same slot as a
  verdict while carrying none — a JRuby lane sat broken for 15 consecutive runs
  looking exactly like this.
- **After merging, check `master`.** `gh run list --branch master --workflow Test
  --limit 1`. A red `master` blocks the next merge. Pass `--workflow Test`: without
  it you get whichever workflow ran last, which has already reported a Dependabot
  success while `Test` was failing on the same commit.

## Coding Conventions

### Style

This project uses [Standard Ruby](https://github.com/standardrb/standard) for consistent formatting. Run `bundle exec standardrb --fix` before committing.

### Ruby version compatibility

The gem supports Ruby 3.2 through 4.0 (including JRuby). When adding features:
- Avoid syntax or APIs that are only available in newer Ruby versions
- Test with the full matrix (see `.github/workflows/test.yml`)
- Be mindful of JRuby compatibility (no C extensions, avoid platform-specific code)

### Naming conventions

- **Classes/modules:** `CamelCase` (Ruby convention)
- **Methods:** `snake_case`
- **Test files:** `snake_case_test.rb` (matching the class they test)
- **Screenshot names:** descriptive, kebab-case or snake_case

### Architecture patterns

- **Value objects** — immutable data carriers (e.g., `Difference`, `Comparison`, `Region`)
- **Strategy pattern** — interchangeable algorithms (e.g., `VipsDriver`/`ChunkyPNGDriver`)
- **Layered comparison** — fast-then-slow strategy in `ImageCompare` (byte → pixel → region)
- **Thread safety** — thread-local state for per-test data, mutex for shared state
- **Test doubles** — use `TestDoubles::TestDriver` and `TestDoubles::TestPath` (see `test/support/test_doubles.rb`)

### What to avoid

- **Service objects** — this codebase prefers explicit method calls over service object wrappers
- **Global state mutation at runtime** — configuration should be set once before tests
- **Monkey-patching** — prefer composition over patching Capybara internals

## Pull Request Guidelines

### Before submitting

1. **Run the full test suite** — `rake test` should pass
2. **Run the linter** — `bundle exec standardrb` should pass
3. **Add tests** for new functionality or bug fixes
4. **Update docs** if changing behavior or adding features
5. **Update CHANGELOG.md** under the `[Unreleased]` section

### PR description

Include:
- **What** changed (one-line summary)
- **Why** it changed (motivation, related issue)
- **How** it was tested
- **Screenshots** if the change affects visual output

### Review process

1. A maintainer will review your PR
2. Address review feedback with additional commits (no force-pushing)
3. Once approved, a maintainer will merge

### Testing guidelines

- **Unit tests** go in `test/unit/` and test a single class in isolation. Use test doubles from `test/support/test_doubles.rb` rather than testing with real image files or browsers.
- **Integration tests** go in `test/integration/` and exercise the full capture → compare → report pipeline with a real browser. These are slower and require Chrome.
- **Driver contract tests** (`test/support/driver_contract_tests.rb`) verify that all image processing drivers meet the same interface. Add a contract test when adding a new driver method.
- **Test environment isolation:** each unit test snapshots and restores `Capybara::Screenshot` and `Capybara::Screenshot::Diff` global state. Don't mutate globals outside of setup/teardown.

## Adding a New Driver

1. Create `lib/capybara/screenshot/diff/drivers/new_driver.rb` inheriting from `BaseDriver`
2. Implement required methods: `load_images`, `from_file`, `save_image_to`, `same_pixels?`, `find_difference_region`, `crop`, `add_black_box`, `draw_rectangles`, `resize_image_to`
3. Register in `Utils.detect_available_drivers` and `Utils.find_driver_class_for`
4. Add driver contract tests in `test/unit/drivers/new_driver_test.rb`
5. Add integration tests exercising the new driver

## Adding a New Reporter

1. Create `lib/capybara_screenshot_diff/reporters/new_reporter.rb`
2. Implement `record(assertions)` and `finalize` methods
3. Register with `CapybaraScreenshotDiff.reporters << MyReporter.new`
4. Add tests in `test/unit/reporters/`

## Releasing

To release a new version:

1. Update the version number in [lib/snap_diff/version.rb](lib/snap_diff/version.rb) — the
   only place it lives; the gemspec and the legacy
   `lib/capybara/screenshot/diff/version.rb` both read it
2. Update [CHANGELOG.md](CHANGELOG.md) with the new version and date
3. Go to [Actions → Release](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/release.yml),
   click **Run workflow** and enter the version number. The workflow verifies the version
   against `lib/`, tests, tags, publishes **both** gem names, and creates the GitHub Release.

**Do not use `rake release`.** It is inherited from `bundler/gem_tasks` and publishes only
`capybara-screenshot-diff`, skipping the `snap_diff-capybara` mirror — the two gems must
never diverge in version. The full runbook, including the trusted-publishing prerequisites
and what to do when a run fails halfway, is in [docs/RELEASE_PREP.md](docs/RELEASE_PREP.md).
