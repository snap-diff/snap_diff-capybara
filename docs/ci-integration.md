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

The report also lists *new* screenshots — captured with no committed baseline — each with the
`git add` that makes it the baseline. On CI a new screenshot fails its test, so `if: failure()`
uploads it. If you set `SnapDiff.config.record = :once` on CI, a run whose only news is a new
screenshot passes: upload with `if: always()` to still get the report.

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

## Accept or reject screenshots in the browser

A static page, hosted on your repository's own GitHub Pages, that lists every changed and new
screenshot of a CI run with its diff. A reviewer marks each one Accept or Reject and presses
Submit. The accepted images land as **one commit on the PR branch**, byte-identical to what CI
captured, and **one PR comment** lists what was accepted (with the commit SHA) and rejected. The
check stays red for the rejected ones. Once the page URL answers,
[`upload-screenshots`](#2-reusable-composite-action-recommended) links to it from the job summary,
and from the PR comment when `pr-comment: 'true'`.

### Install

Copy this workflow:

```yaml
# .github/workflows/review-page.yml
name: Review page
on:
  push:
    branches: [ main ]       # your default branch
    paths: [ Gemfile.lock ]
  workflow_dispatch:
permissions:
  contents: write
concurrency:
  group: snap-diff-review-page   # two racing runs would reject one push
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: snap-diff/snap_diff-capybara/.github/actions/deploy-review-page@master
```

Run it once with "Run workflow". It publishes `snap-diff/index.html` to the `gh-pages` branch
(created if missing, everything else on the branch is left alone) and prints the page URL
(`https://<owner>.github.io/<repo>/snap-diff/`) in the job summary. Then, once the branch exists,
enable Pages: Settings -> Pages -> Build and deployment -> Deploy from a branch -> `gh-pages` /
`(root)`.

### Auto-update

The page ships inside the gem. The workflow reads the `snap_diff-capybara` version locked in
`Gemfile.lock` (or `gems.locked`) and publishes the page from that exact release. A Dependabot
bundler bump changes `Gemfile.lock`, so merging it republishes the page. A gem that is locked from
git or a path has no release to read: pass `page:` with a path to an `index.html` instead.

### The token

The page asks the reviewer for a fine-grained personal access token. Create it under Settings ->
Developer settings -> Fine-grained tokens:

- Repository access: only this repository
- Actions: Read
- Contents: Read and write
- Pull requests: Read and write
- A short expiry

### Limits

- Same-repository PRs only. A PR from a fork is refused: the token cannot write to the fork.
- It reads the run's report artifact, so it works until `retention-days` (default `2`) expires.
  After that, re-run CI.
- Pages must be served from the `gh-pages` branch (root) of this repository: not the "GitHub
  Actions" source, not `main`:`/docs`. A user-site repository named `<owner>.github.io` is not
  supported.
- A custom-domain site must keep the `/<repo>/` path segment, so the page stays at
  `/<repo>/snap-diff/`.
- If the PR branch has new commits since the CI run, nothing is written: re-run CI and review again.

### Security model

The page cross-checks the ids in its link (run, PR and artifact) against GitHub before it writes
anything. It writes only `.png` and `.webp` image bytes, only at the screenshot paths CI listed in
`snap_diff_manifest.json`. It never force-pushes: a moved branch is an error, not an overwrite. The
token is kept in memory for the page load and is never stored. The page serves only the
repository that hosts it, and refuses to run inside a frame or a window opened by another page.

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
        env:
          SNAP_DIFF_ACCEPT_SCREENSHOTS: "1"    # record: :all for this job only

      - name: Commit updated baselines
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add doc/screenshots/
          git diff --staged --quiet || git commit -m "chore: update screenshot baselines"
          git push
```

</details>

`SNAP_DIFF_ACCEPT_SCREENSHOTS` puts the run in the `:all` record mode: every screenshot is
compared to its committed baseline, one that differs becomes the new baseline, one with no
baseline yet is recorded, and the run exits green with a summary of what it re-recorded
(`3 changed (3 re-recorded)`). A failing test that has nothing to do with screenshots still fails
the job. See [Record modes](configuration.md#record-modes--accepting-changes) for the mode itself.

Set the variable on this job only. The gem cannot tell a variable set on one job from one exported
to every job, and on a verification job it would accept every change. Do not put
`record = :all` in `test_helper.rb` for the same reason; under CI the gem refuses a `:all` that
comes from code.

Record in the same environment that verifies (OS, browser, fonts). A baseline recorded elsewhere
is often worthless, which is why this job runs on CI at all.

Two things this minimal recipe does not do:

- It keeps the committed PNGs, not the HTML report or the diff images. Add an
  [upload step](#2-reusable-composite-action-recommended) without an `if: failure()` guard if you want them.
- A push made with the default `GITHUB_TOKEN` does not start the ordinary verification
  workflow. Review the images in the pushed commit, then run the normal check against it.

**How it works:**
1. Go to Actions → "Update Screenshot Baselines" → "Run workflow"
2. Enter the branch name (e.g. your PR branch)
3. The workflow records new and changed baselines, commits, and pushes

[← Back to README](../README.md)
