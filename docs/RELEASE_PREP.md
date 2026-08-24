# Release runbook

Maintainer-only. This file is deliberately excluded from the packaged gem.

Releases are **one `workflow_dispatch`**. There is no `rake release`, no manual
`gem push`, and no local credential. Everything below either happens in CI or has to
be committed to `master` before you dispatch.

## What the Release workflow does

[`.github/workflows/release.yml`](../.github/workflows/release.yml), dispatched from
[Actions → Release](https://github.com/snap-diff/snap_diff-capybara/actions/workflows/release.yml)
with a single `version` input (e.g. `2.0.0`, or `2.1.0.beta1`):

1. **Verify version** — reads `Capybara::Screenshot::Diff::VERSION` out of `lib/` and
   fails if it does not equal the input. This is the guard that makes the dispatch
   safe: the version lives in `lib/snap_diff/version.rb` and must already be on
   `master`.
2. **Test** — `bundle exec rake test:unit` on Ruby 4.0.
3. **Tag** — creates and pushes `v<version>`. Idempotent: it skips if the tag already
   exists at HEAD and fails loudly if it exists at a *different* commit. A failed run
   can be re-dispatched without cleanup.
4. **Publish `capybara-screenshot-diff`** — `rubygems/release-gem@v1`, via RubyGems
   trusted publishing (OIDC). No API key is stored anywhere.
5. **Publish the `snap_diff-capybara` mirror** — the same gemspec is loaded, renamed
   in memory, built and pushed. The mirror gemspec is *generated in CI, never
   committed*, so local `gem build` and the `gemspec` directive in `gems.rb` stay
   unambiguous. It reuses the credential `release-gem` already set up, which covers
   any gem whose rubygems.org settings trust this repo + workflow.
6. **GitHub Release** — body links to the CHANGELOG and upgrade guide **at the tag**.
   Prerelease status is auto-detected from the tag, so `v2.1.0.beta1` lands as
   *Pre-release* and never displaces the *Latest* badge.

### Prerequisites that live outside this repo

- **Both** gem names must trust this repo + `release.yml` as a trusted publisher on
  rubygems.org — `capybara-screenshot-diff` **and** `snap_diff-capybara`. If only one
  does, step 4 or 5 fails after the tag is already pushed; re-dispatch after fixing.
- If tag protection rules are ever added to this repo, `v*` must allow
  `github-actions[bot]` to push — that is how step 3 creates the tag.

## Before you dispatch

- [ ] `lib/snap_diff/version.rb` bumped to the exact version you will type into the
      workflow. Nothing else holds a version — the gemspec, the legacy
      `capybara/screenshot/diff/version.rb` and the mirror gemspec all read it.
- [ ] `CHANGELOG.md` has a section for this version with a real date (not
      `unreleased`), written for someone upgrading from the last **stable** release
      rather than from the previous prerelease.
- [ ] Docs carry no stale version pins — `README.md`, `docs/UPGRADING.md`,
      `docs/snapdiff.md`. Grep for the previous version string.
- [ ] No unfilled placeholders in the section: `grep -n 'PLACEHOLDER' CHANGELOG.md`.
      Each is an HTML comment marking a feature that landed in a parallel lane — fill it
      from that PR's description, or delete it if the feature did not make this release.
- [ ] **Releasing 2.0.0: swap every install snippet from the `2.0.0.beta4` pin to
      `"~> 2.0"`,** and delete the "final is not out yet" clauses next to them. Until
      2.0.0 exists on rubygems, `gem "capybara-screenshot-diff", "~> 2.0"` hard-fails
      `bundle install` (Bundler never resolves a prerelease from a plain requirement), so
      the good pin has to land *with* the release, not before it. The snippets live in
      `README.md`, `CHANGELOG.md`, `docs/UPGRADING.md` (×2) and `docs/migration-guide.md` —
      re-grep rather than trusting that list:
      `grep -rn 'capybara-screenshot-diff.\{0,4\}2\.0' README.md CHANGELOG.md docs/`
- [ ] `mise x ruby@4.0.6 -- bundle exec rake test` (full suite, both gates) and
      `mise x ruby@4.0.6 -- bundle exec standardrb` are green.
- [ ] CI is green on `master` at the commit you are releasing — the workflow only
      runs `test:unit`, which is a subset.
- [ ] `gem build capybara-screenshot-diff.gemspec` and inspect the file list if
      anything touched the gemspec allow-list. `*.gem` is gitignored, but delete the
      artifact anyway — a stale one in the working tree is confusing.

### Prereleases

Nothing special to configure. Use a prerelease version string (`2.1.0.beta1`) in
`version.rb` and in the dispatch input. RubyGems never resolves a prerelease by
default, and GitHub marks the release *Pre-release* on its own.

## After

- [ ] Both gems visible and at the same version:
      [capybara-screenshot-diff](https://rubygems.org/gems/capybara-screenshot-diff),
      [snap_diff-capybara](https://rubygems.org/gems/snap_diff-capybara). A version
      published under only one name is the failure mode to watch for — the two gems
      ship identical files and the dual-install guard assumes they never diverge.
- [ ] GitHub Release created, with the right Latest/Pre-release status.
- [ ] `gem install capybara-screenshot-diff -v <version>` in a scratch dir resolves.

## If a run fails halfway

Re-dispatch the same version. The tag step is idempotent and `gem push` rejects a
duplicate version, so the only real hazard is a mirror push that failed for a
credential reason — fix the trusted-publisher settings and re-dispatch. **Never**
retag: the workflow refuses to move an existing tag and you should not do it by hand
either.
