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

### 2. Upload artifacts (manual setup)

This is the full YAML so you understand what each step does:

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      # Install libvips for the :vips driver (optional — skip if using :chunky_png)
      - name: Install libvips
        run: sudo apt-get install -y libvips-dev

      - name: Run tests
        run: bundle exec rake test

      # Upload HTML report — renders inline in Actions UI (no download needed)
      - name: Upload screenshot report
        if: failure()
        uses: actions/upload-artifact@v7
        with:
          name: screenshot-report
          path: doc/screenshots/snap_diff_report.html
          archive: false
          retention-days: 2

      # Upload full report with images (for offline review)
      - name: Upload full screenshot report
        if: failure()
        uses: actions/upload-artifact@v7
        with:
          name: screenshot-report-full
          path: doc/screenshots/
          retention-days: 2
```

### 3. Or use the reusable action (one line)

Instead of the manual upload steps above, reference our composite action directly:

```yaml
      - name: Run tests
        run: bundle exec rake test

      - name: Upload screenshot reports
        if: failure()
        uses: snap-diff/snap_diff-capybara/.github/actions/upload-screenshots@master
        with:
          name: screenshots
```

This uploads diffs, Capybara failure screenshots, and the HTML report (inline + full) in one step.

**Inputs:**

| Input | Default | Description |
|-------|---------|-------------|
| `name` | (required) | Artifact name prefix |
| `report-path` | `doc/screenshots` | Path to HTML report directory |
| `retention-days` | `2` | Days to retain artifacts |

### 4. PR comment with link to report (optional)

Automatically comment on the PR pointing to the artifact. Uses `find-comment` to update existing comments instead of creating duplicates:

```yaml
      - name: Find existing comment
        if: failure() && github.event_name == 'pull_request'
        uses: peter-evans/find-comment@v3
        id: find-comment
        with:
          issue-number: ${{ github.event.pull_request.number }}
          comment-author: 'github-actions[bot]'
          body-includes: 'Screenshot diffs detected'

      - name: Comment PR with report link
        if: failure() && github.event_name == 'pull_request'
        uses: peter-evans/create-or-update-comment@v5
        with:
          comment-id: ${{ steps.find-comment.outputs.comment-id }}
          issue-number: ${{ github.event.pull_request.number }}
          edit-mode: replace
          body: |
            ### Screenshot diffs detected
            [View report](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}#artifacts)
```

**Required:** Add permissions to the job for PR commenting to work:

```yaml
jobs:
  test:
    permissions:
      contents: read
      pull-requests: write
```

## Update Baselines in CI

When intentional UI changes are made, baselines need to be re-recorded. You can do this locally:

```bash
RECORD_SCREENSHOTS=1 bundle exec rake test
git add test/fixtures/screenshots/
git commit -m "chore: update screenshot baselines"
```

Or add a workflow that maintainers can trigger manually:

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

      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Install libvips
        run: sudo apt-get install -y libvips-dev

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

**How it works:**
1. Go to Actions → "Update Screenshot Baselines" → "Run workflow"
2. Enter the branch name (e.g. your PR branch)
3. The workflow records new baselines, commits, and pushes

**Safety:**
- Only maintainers with write access can trigger `workflow_dispatch`
- The commit uses `git diff --staged --quiet ||` to skip empty commits
- `GITHUB_TOKEN` pushes don't trigger subsequent CI runs ([by design](https://docs.github.com/actions/using-workflows/events-that-trigger-workflows))

[← Back to README](../README.md)
