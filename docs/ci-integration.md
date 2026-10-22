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

## Accept screenshots from the pull request

When a CI run fails on screenshot diffs, a reviewer can accept the new pixels without checking out the
branch. In the HTML report (the inline link in the PR comment), each changed or new screenshot has
Accept and Reject buttons (keys `Y` and `N`). The "Copy review command" button copies a line like
`/snap-diff accept run=123 linux/cuprite/index.png@0123456789abcdef`. Pasting it as a PR comment starts
a workflow that commits those exact files from that run's report artifact to the PR branch with the
repository's own `GITHUB_TOKEN`, replies with the commit, and re-runs CI. The buttons appear only in
reports built on GitHub Actions.

To install it, copy this workflow. Set `screenshots-path` to your `save_path`. `ci-workflow` is
optional: it names your test workflow, which needs an `on: workflow_dispatch` trigger. Without it the
reply asks you to re-run CI by hand, because a push made with `GITHUB_TOKEN` does not start workflows.

```yaml
# .github/workflows/snap-diff-accept.yml
name: Accept screenshots

on:
  issue_comment:
    types: [created]

jobs:
  accept:
    if: >-
      github.event.issue.pull_request &&
      startsWith(github.event.comment.body, '/snap-diff accept') &&
      contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association)
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: write
      pull-requests: write
      actions: write   # read is enough if you leave out ci-workflow
    concurrency:
      group: snap-diff-accept-${{ github.event.issue.number }}
      cancel-in-progress: false
    steps:
      - uses: snap-diff/snap_diff-capybara/.github/actions/accept-screenshots@master
        with:
          screenshots-path: doc/screenshots
          ci-workflow: test.yml
```

`issue_comment` workflows run only from the default branch, so merge this file first. Until then the
comment does nothing.

Commenters need write access to the repository. The workflow checks the permission API as well as the
comment's `author_association`, so read-only collaborators are refused.

Limits:

- Pull requests from the same repository only. A fork PR is refused.
- Git LFS paths are refused. Accept those locally.
- Screenshot paths may use only `A-Z a-z 0-9 . _ - /` (no spaces) and must sit under `screenshots-path`.
- The report artifact must still exist. `upload-screenshots` keeps it `retention-days` days (default 2).
- Only the PR's current head can be accepted. After a new push, review the new run's report.
- Only the last capture of a file can be accepted. Earlier captures of it show a note instead of the buttons.

Security: the workflow never checks out or runs the PR's code. It downloads the report artifact, takes
the paths from the report's manifest, and commits a file only if its SHA-256 matches the hash in the
reviewer's command and its bytes are a PNG or WebP. It pushes only to the PR branch, and only while
that branch is still at the commit the run tested. The design does rely on trust you already extend:
whoever opens a same-repository PR can already push to the repository, and their CI run produces the
artifact. Beyond that, the permission check and your branch protection limit the damage. Do not enable
this for forks, and do not give the bot a ruleset bypass: with branch protection in place, a push the
rules reject fails instead of landing.

[← Back to README](../README.md)
