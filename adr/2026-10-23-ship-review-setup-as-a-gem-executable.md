---
status: proposed
date: 2026-10-23
decision-makers: "@pftg"
---

# Ship review setup as a gem executable

## Context and Problem Statement

The review page ([Review PR screenshots on a sign-in review page backed by a self-hosted GitHub App and Worker](2026-10-23-review-screenshots-on-a-sign-in-page.md)) needs, per adopting project, a GitHub App, a Cloudflare Worker holding the App's client secret, the App installed on the repository, and the page URL in the CI workflow. Done by hand that is about nine steps across GitHub, Cloudflare and the workflow file. The maintainer's requirement is "from empty project to setup all this as simple as possible".

The gem has no way to give consumers a command today: its gemspec ships no executables ("No executables" comment), and the only task, `snap_diff:clean`, is defined in the gem's own `Rakefile`, which consumers never load. (`docs/organization.md` tells users to run `rake snap_diff:clean`; that task is not available to them.)

## Decision

Add a gem executable, `bundle exec snap_diff setup`, that takes a project with the gem installed to a working review link in about ten minutes and three clicks. It works with or without Rails. Prerequisites: a GitHub repository the user administers, a free Cloudflare account, Node (for `npx`).

The command, in order:

1. Writes `.github/workflows/screenshots.yml` (run the tests; on failure run `upload-screenshots`) when no workflow uses `upload-screenshots` yet; otherwise leaves workflows alone.
2. Deploys the review Worker with `npx wrangler deploy` from the gem's `worker/` and `lib/snap_diff/review/`, which opens the Cloudflare login the first time (**click 1**), and reads the deployed URL.
3. Creates the GitHub App through the [manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest): serves a one-page form on `localhost` that posts the manifest (name, permissions Contents: write, Pull requests: write, Actions: read, Metadata: read, callback URL = the Worker URL, no webhook) to GitHub; the user clicks **Create GitHub App** (**click 2**); GitHub redirects back to `localhost` with a code, which the command converts within the hour into the client ID and secret; it stores them with `npx wrangler secret put GITHUB_CLIENT_SECRET` and the client ID as a Worker variable, then redeploys.
4. Opens the App's install page; the user clicks **Install** on the repository (**click 3**; for organisation repositories an organisation owner must do this).
5. Writes the Worker URL into the workflow as `review-url:` on `upload-screenshots`.

It prints what it did and the next step ("commit and push; the next failing PR comment will link to the review page"). Running it again after a gem upgrade redeploys the page and changes nothing else. Non-goals: hosting anywhere but Cloudflare, GitHub Enterprise Server, creating the GitHub repository or the Cloudflare account, committing or pushing for the user.

## Consequences

- Good, because the setup is one command plus three clicks, and the same command updates the page.
- Good, because the secret goes straight from GitHub's manifest conversion into Cloudflare and is never printed or written to disk.
- Good, because the manual steps stay documented as the fallback, and they are exactly what the command automates.
- Bad, because the gem gains its first executable and a dependency on Node being present (only for this command).
- Bad, because the manifest flow's redirect to a local command is unproven until the review page ADR's spike.

## Implementation Plan

- **Affected paths**: `exe/snap_diff` (new; parses `setup`, prints usage otherwise); `lib/snap_diff/setup.rb` (new; the five steps, each a small method; shells out with argument arrays, never a shell string); `capybara-screenshot-diff.gemspec` (allow-list `exe/`, set `bindir "exe"` and `executables ["snap_diff"]`, update the "No executables" comment, make sure `worker/` ships); `worker/` (from the review page ADR); `docs/ci-integration.md` (setup section: the command, then the manual steps as fallback); `README.md` (one line in the CI section); `docs/organization.md` (fix the `rake snap_diff:clean` claim, e.g. point to the command or remove it).
- **Dependencies**: none added to the gem; `npx wrangler` at run time.
- **Patterns to follow**: `upload-screenshots` and the earlier `deploy-review-page` action for the workflow shape; fail fast with one clear message per missing prerequisite (no Node, not a git repository, no GitHub remote).
- **Patterns to avoid**: storing the App secret or PEM in the repository or on disk; interactive prompts beyond the three browser clicks; editing workflows that already configure `upload-screenshots` other than adding `review-url`.

### Verification

- [ ] On an empty sample Rails app with the gem added, `bundle exec snap_diff setup` finishes in about ten minutes with three clicks; after commit and push, a PR with a changed screenshot gets a comment linking to the review page, and sign-in plus Commit works.
- [ ] Re-running the command changes no files and redeploys the Worker.
- [ ] Unit tests cover the workflow writing (new file vs existing `upload-screenshots` vs already set `review-url`) and the manifest JSON (permissions, callback URL), with the shell-outs stubbed.
- [ ] `gem build` includes `exe/snap_diff` and `worker/`; `gem install` exposes `snap_diff`.
- [ ] No secret appears in the command's output or in any file it writes.

## Alternatives Considered

- Rake task `snap_diff:setup`: consumers cannot load the gem's rake tasks without a Railtie or a `require` in their Rakefile, and non-Rails projects would need their own wiring.
- Manual setup guide only (about nine steps): kept as the documented fallback, but too slow and error-prone as the main path.
- A shared hosted instance needing only "install the app": rejected in the review page ADR for trust reasons.
