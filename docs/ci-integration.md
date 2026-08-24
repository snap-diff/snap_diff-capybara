# CI & Non-Rails Integration

## Non-Rails Projects (Hugo, Jekyll, Static Sites)

```ruby
# test/test_helper.rb
require 'snap_diff/static'

SnapDiff.serve("_site")  # or "public", "build", "dist"
```

<details>
<summary>Legacy names (still supported)</summary>

```ruby
require 'capybara_screenshot_diff/static'
CapybaraScreenshotDiff.serve("_site")
```
</details>

This sets up Capybara to serve static files and configures screenshot paths automatically.

## .gitignore Setup

See the [Quick Start section](../README.md#quick-start-5-minutes) in the README for recommended `.gitignore` patterns.

Only commit the baseline screenshots (e.g., `homepage.png`). The `.base.png`, `.diff.png`, `.heatmap.diff.png`, and report files are regenerated on every test run.

## GitHub Actions Integration

### 1. Enable the HTML report

Add to your test helper:

```ruby
require 'snap_diff/reporters/html'            # canonical
# require 'capybara_screenshot_diff/reporters/html'   # legacy, same thing
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
        run: bin/rails test:system   # not `rake test` — it skips test/system/

      - name: Upload screenshot reports
        if: failure()
        uses: snap-diff/snap_diff-capybara/.github/actions/upload-screenshots@master
        with:
          name: screenshots
          pr-comment: 'true'
```

The three workflows on this page all run `bin/rails test:system`, because `rake test` and
`rails test` skip `test/system/` and report `0 runs` — a green CI job that compared nothing.
Not on Rails? Substitute whatever task loads your Capybara tests.

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

For consistent CI environments (libvips, font antialiasing disabled), use the setup action:

```yaml
      - uses: snap-diff/snap_diff-capybara/.github/actions/setup-ruby-and-dependencies@master
        with:
          ruby-version: '4.0'
          cache-apt-packages: true
```

This installs Ruby, libvips (with apt caching), and disables font antialiasing for consistent rendering across CI runs.

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

      - run: bin/rails test:system   # not `rake test` — it skips test/system/

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
        run: bin/rails test:system   # not `rake test` — it skips test/system/

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

When intentional UI changes are made, baselines need to be re-recorded. Baselines are
read from git, so accepting a change is a commit — the failing run has already written
the new capture to the baseline path:

```bash
bin/rails test:system                  # fails, and rewrites the changed baselines
git status                             # review what moved
git add doc/screenshots/               # the default save_path; adjust if you changed it
git commit -m "chore: update screenshot baselines"
```

With the [recommended `.gitignore`](../README.md#quick-start-5-minutes) in place, `git add
doc/screenshots/` stages only the baselines — the `.diff.png` / `.base.png` artifacts are
ignored.

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

      - name: Record baselines
        run: bin/rails test:system
        continue-on-error: true    # the run fails by design; it rewrites the baselines
        env:
          CI: ""                   # see below — without this, a NEW screenshot is never written

      - name: Commit updated baselines
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add doc/screenshots/
          git diff --staged --quiet || git commit -m "chore: update screenshot baselines"
          git push
```

</details>

> **Set the record mode, or clear `CI`, to let this job record a *new* baseline.** With
> nothing set, a missing baseline fails whenever `ENV["CI"]` is set and non-empty — so on a
> stock GitHub Actions runner a screenshot with no committed baseline raises `No existing
> screenshot found for …`. `SnapDiff.config.record = :once`
> (or clearing `CI` for this one step, or the older `SnapDiff.config.fail_if_new = false`)
> records new baselines instead. *Changed* baselines are rewritten either way; only new ones
> need this. See [Record modes](configuration.md#record-modes--accepting-changes).
>
> The screenshot itself **is** written before the raise ([`screenshot_matcher.rb`](https://github.com/snap-diff/snap_diff-capybara/blob/master/lib/snap_diff/screenshot_matcher.rb)
> — `capture_screenshot` precedes `fail_if_new_screenshot`), so the `git add` the message names
> is a command you can actually run. But the raise still fails the test it happened in, and a red
> job usually never reaches the commit step — which is why a recording job sets the mode rather
> than relying on the files being there.
>
> **`record = :all` is not the mode for this job** — it refuses to run under CI, because it
> would accept every *changed* rendering unreviewed as well. `:once` records what is new and
> keeps comparing everything that already has a baseline.

**How it works:**
1. Go to Actions → "Update Screenshot Baselines" → "Run workflow"
2. Enter the branch name (e.g. your PR branch)
3. The workflow records new and changed baselines, commits, and pushes

[← Back to README](../README.md)
