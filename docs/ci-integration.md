# CI & Non-Rails Integration

## Non-Rails Projects (Hugo, Jekyll, Static Sites)

```ruby
# test/test_helper.rb
require 'capybara_screenshot_diff/static'

CapybaraScreenshotDiff.serve("_site")  # or "public", "build", "dist"
```

This sets up Capybara to serve static files and configures screenshot paths automatically.

## .gitignore Setup

Add these patterns to your `.gitignore` — diff artifacts are generated at runtime and should not be committed:

```gitignore
# Screenshot diff artifacts (generated, not committed)
*.diff.png
*.base.png
*.diff.webp
*.base.webp
snap_diff_report.html
```

Only commit the baseline screenshots (e.g., `homepage.png`). The `.base.png`, `.diff.png`, `.heatmap.diff.png`, and report files are regenerated on every test run.

## GitHub Actions Integration

### 1. Enable the HTML report

Add to your test helper:

```ruby
require 'capybara_screenshot_diff/reporters/html'
```

### 2. Reusable composite action (recommended)

The simplest way — one step handles artifact upload, job summary, and PR comments:

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write  # Required for PR comments

    steps:
      - uses: actions/checkout@v6

      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Run tests
        run: bundle exec rake test

      - name: Upload screenshot reports
        if: failure()
        uses: snap-diff/snap_diff-capybara/.github/actions/upload-screenshots@master
        with:
          name: screenshots
          pr-comment: 'true'
```

That's it. On failure, this will:
- Upload diff images + HTML report as artifacts
- Post a PR comment with links to the inline report and full artifact download
- Add a job summary with report links (visible in the Actions UI)

#### Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `name` | (required) | Artifact name prefix |
| `report-path` | `doc/screenshots` | Path to HTML report directory |
| `retention-days` | `2` | Days to retain artifacts |
| `pr-comment` | `false` | Post PR comment with report link (requires `pull-requests: write`) |

#### Outputs

| Output | Description |
|--------|-------------|
| `report-url` | Direct URL to the inline HTML report artifact |
| `report-full-url` | Direct URL to the full report artifact (with images) |

### 3. Ruby + libvips setup action

For consistent CI environments (libvips, standardized fonts, hinting disabled),
use the setup action:

```yaml
      - uses: snap-diff/snap_diff-capybara/.github/actions/setup-ruby-and-dependencies@master
        with:
          ruby-version: '4.0'
          cache-apt-packages: true
```

This installs Ruby, libvips (with apt caching), installs the core font stack,
and disables font hinting for consistent rendering across CI runs.

For local or Docker setups, see `docs/os-setup.md`.

#### Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `ruby-version` | (required) | Ruby version to install |
| `cache-apt-packages` | `false` | Cache libvips apt packages for faster runs |
| `ruby-cache-version` | — | Bundler cache version key |

### 4. Full example with both actions

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
      pull-requests: write

    steps:
      - uses: actions/checkout@v6

      - uses: snap-diff/snap_diff-capybara/.github/actions/setup-ruby-and-dependencies@master
        with:
          ruby-version: '4.0'
          cache-apt-packages: true

      - run: bundle exec rake test

      - uses: snap-diff/snap_diff-capybara/.github/actions/upload-screenshots@master
        if: failure()
        with:
          name: screenshots
          pr-comment: 'true'
```

### 5. Manual setup (without composite actions)

If you prefer full control, here's the expanded YAML:

<details>
<summary>Expand manual setup</summary>

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Install libvips
        run: sudo apt-get install -y libvips-dev

      - name: Run tests
        run: bundle exec rake test

      - name: Upload screenshot report
        if: failure()
        uses: actions/upload-artifact@v7
        with:
          name: screenshot-report
          path: doc/screenshots/snap_diff_report.html
          archive: false
          retention-days: 2

      - name: Upload full report with images
        if: failure()
        uses: actions/upload-artifact@v7
        with:
          name: screenshot-report-full
          path: doc/screenshots/
          retention-days: 2
```

</details>

## Update Baselines in CI

When intentional UI changes are made, baselines need to be re-recorded. You can do this locally:

```bash
RECORD_SCREENSHOTS=1 bundle exec rake test
git add test/fixtures/screenshots/
git commit -m "chore: update screenshot baselines"
```

Or add a workflow that maintainers can trigger manually:

<details>
<summary>Expand update-baselines workflow</summary>

```yaml
# .github/workflows/update-baselines.yml
name: Update Screenshot Baselines

on:
  workflow_dispatch:
    inputs:
      branch:
        description: 'Branch to update baselines on'
        required: true
        default: 'main'

permissions:
  contents: write

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          ref: ${{ inputs.branch }}

      - uses: snap-diff/snap_diff-capybara/.github/actions/setup-ruby-and-dependencies@master
        with:
          ruby-version: '4.0'
          cache-apt-packages: true

      - name: Record new baselines
        run: RECORD_SCREENSHOTS=1 bundle exec rake test
        continue-on-error: true

      - name: Commit updated baselines
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add test/fixtures/ doc/screenshots/
          git diff --staged --quiet || git commit -m "chore: update screenshot baselines"
          git push
```

</details>

**How it works:**
1. Go to Actions → "Update Screenshot Baselines" → "Run workflow"
2. Enter the branch name (e.g. your PR branch)
3. The workflow records new baselines, commits, and pushes

[← Back to README](../README.md)
