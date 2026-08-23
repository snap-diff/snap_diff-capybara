# Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/snap-diff/snap_diff-capybara.
This project is intended to be a safe, welcoming space for collaboration, and contributors are expected
to adhere to the [Contributor Covenant](CODE_OF_CONDUCT.md) code of conduct.

## Development Setup

### Prerequisites

- **Ruby 3.2+** (the project tests against 3.2–4.0)
- **libvips 8.9+** — required. It is the only image backend, and `ruby-vips` is a runtime dependency of the gem. Install the system library with:
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

- **Value objects** — immutable data carriers (e.g., `ComparisonResult`, `Comparison::Images`, `Region`)
- **Layered comparison** — fast-then-slow strategy in `SnapDiff::Comparison` (byte → pixel → region)
- **One image backend** — `SnapDiff::Drivers::VipsDriver`. 2.1 removed the driver abstraction; do not reintroduce a strategy layer around it
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
- **Driver contract tests** (`test/support/driver_contract_tests.rb`) pin the interface `Comparison`, `ImagePreprocessor`, `Screenshoter` and `AnnotationService` all call on `VipsDriver` — signatures, arity, and `load_images` slot order. It is no longer a *shared* contract (2.1 left one backend), but drift in any of those would break the callers silently. Extend it when you change a method the callers use.
- **Test environment isolation:** each unit test snapshots and restores `SnapDiff.config` by instance variable. Don't mutate global config outside of setup/teardown.

## Adding a New Reporter

1. Create `lib/snap_diff/reporters/new_reporter.rb`
2. Implement `record(assertions)`, `finalize` and `summary` methods
3. Register with `SnapDiff::Reporting.register(MyReporter.new)`
4. Add tests in `test/unit/reporters/`

## Releasing

To release a new version:

1. Update the version number in [lib/snap_diff/version.rb](lib/snap_diff/version.rb)
2. Update [CHANGELOG.md](CHANGELOG.md) with the new version and date
3. Create a GitHub Release:
   - Go to [Actions → Release](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/release.yml)
   - Click **Run workflow**, enter the version number
   - The workflow will: test → tag → publish to RubyGems → create GitHub Release

Or manually:

```bash
bundle exec rake release
```

This creates a git tag, pushes commits and tags, and pushes the `.gem` file to [rubygems.org](https://rubygems.org).
