---
status: proposed
date: 2026-10-23
decision-makers: "@pftg"
consulted: product, design and engineering review seats; two independent security reviews; a cold-eyes pitch review
informed: snap_diff-capybara contributors
---

# Review PR screenshots on a sign-in review page backed by a self-hosted GitHub App and Worker

## Context and Problem Statement

snap_diff-capybara keeps baselines as files committed in git: a test compares a capture against `git show HEAD:<path>`, so accepting a changed screenshot means committing the new capture at the baseline path. On a failing pull-request run the gem already writes `snap_diff_report.html` and `snap_diff_manifest.json` (each changed or new screenshot with its git-root path, its file in the report directory and its SHA-256), and the `upload-screenshots` action uploads them and comments on the PR. What is missing is a way for a reviewer to accept or reject screenshots without checking out the branch.

Three approaches were built and rejected by the maintainer:

1. A static review page on GitHub Pages that commits through the GitHub API with a fine-grained personal access token pasted by the reviewer. It worked end to end (PR #314: committed bytes identical to the CI artifact, CI re-ran on its own, failing tests went from 11 to 5), but pasting a token on every visit was judged "very unfriendly".
2. Copying a `/snap-diff accept …` command from the report into a PR comment, carried out by an `issue_comment` workflow with `GITHUB_TOKEN`: "very complicated".
3. A "Commit decisions" button in the report that opens a prefilled GitHub issue, carried out by the same workflow: "too complicated".

The question: how does a reviewer approve or reject PR screenshots from one page, in a private repository, with no token handling and a setup a developer can finish quickly?

## Decision Drivers

- Reviewers must not paste tokens or commands; one sign-in, then clicks.
- Private repositories must work.
- Setup from an empty project must be short (target ≈10 minutes, see the setup ADR).
- Platform facts (verified 2026-10-22/23):
  - a static page cannot hold a secret; repository secrets exist only inside Actions runs;
  - GitHub's OAuth code exchange (`github.com/login/oauth/access_token`) requires the client secret even with PKCE, and a CORS preflight to it and to `github.com/login/device/code` returns 404 without `Access-Control-Allow-Origin`, so a browser-only app cannot complete sign-in;
  - GitHub App user access tokens expire after 8 hours and never exceed the user's own permissions;
  - `api.github.com` and the Actions artifact download redirect are CORS-open (unzipped bytes verified identical in Chrome);
  - free GitHub Pages sites are public with no access control;
  - a push made with `GITHUB_TOKEN` does not start workflows, a push made with a user's token does.
- Trust: same-repository PR authors already have write access; nobody outside the adopting company should be able to touch its private code.
- KISS: one default path, at most one escape hatch; delete what the new path makes unnecessary.

## Considered Options

- Personal-access-token review page on GitHub Pages
- PR comment or prefilled issue carried out by an Actions bot
- Self-hosted GitHub App + Cloudflare Worker + sign-in review page
- Shared hosted GitHub App + Worker run by the gem maintainers
- Signed review links with a server-held repository credential
- The PR's "Files changed" tab as the review UI, plus a bot that commits all captures
- A local command-line reviewer

## Decision Outcome

Chosen option: "Self-hosted GitHub App + Cloudflare Worker + sign-in review page", because it is the only option that gives a one-sign-in, click-only review on private repositories without any party outside the adopting company holding access to its code, and it reuses the review page and safeguards already proven on PR #314.

The flow:

1. The PR comment links to the review page (`https://<worker>/#/<owner>/<repo>/pull/<n>?run=<id>`; the repository is in the fragment and never reaches the Worker).
2. The reviewer signs in with GitHub once (PKCE redirect; the Worker's single `POST /token` route adds the client secret and returns an 8-hour user token, kept only in page memory).
3. The page loads the run, its report artifact and the PR through `api.github.com` and lands on the first undecided screenshot: baseline (from the repository at the run's head commit) next to the new capture, diff and heatmap; Space flips baseline/new.
4. **A** accepts, **R** rejects, **J/K** move, **U** undoes; "Accept remaining" for bulk; only the last capture of a file can be decided.
5. `Commit N screenshots to <branch>` writes one commit through the Git Data API whose parent is the reviewed head commit, updates the branch without force, and posts one PR comment. Accepted files are committed with the exact CI bytes; rejected ones are listed on the PR and nothing is committed for them; undecided ones stay failing. CI re-runs because the push is made with the reviewer's token.

### Consequences

- Good, because reviewers sign in once and never handle tokens or commands.
- Good, because a user token can never exceed the reviewer's own permissions, so read-only collaborators cannot commit and each commit carries the reviewer's identity.
- Good, because each company holds its own App secret; the gem maintainers run no service and see no private code.
- Good, because the review page's proven safeguards carry over (link-id cross-check, PNG/WebP magic bytes, no `.git*` paths, size caps, lease-style ref update, CSP with script hash, refusal to run framed or opened by another window).
- Good, because it deletes the comment/issue bot and the report's review controls (~900 lines on this branch).
- Bad, because each adopter needs a free Cloudflare account and must create and install a GitHub App (automated by the setup ADR, but an org owner must approve the install for org repositories).
- Bad, because one unproven assumption remains until the spike: that a GitHub App user token can download artifacts, push so CI re-runs, and work under SAML single sign-on.
- Neutral, because the HTML report goes back to read-only with one "Review & accept →" link.

## Implementation Plan

- **Day-1 spike (gate)**: create a throwaway GitHub App (Contents: write, Pull requests: write, Actions: read, Metadata: read; no webhook), install it on a private repository in an organisation with SAML, sign in through a 30-line page plus `npx wrangler dev`, and with the user token: download an artifact, push a commit to a PR branch through the Git Data API, confirm CI re-runs and that a repository without the app installed is refused. If CI does not re-run, the page dispatches the test workflow (`workflow_dispatch`) after the push. Record results in "More Information" before moving this ADR to `accepted`.
- **Affected paths**:
  - `lib/snap_diff/review/index.html` — revive from commit `f797a96`; replace the token field with "Sign in with GitHub" (PKCE redirect, `POST /token`); take `owner/repo/pull/run` from the URL fragment; apply the design in the pitch (`A`/`R`/`J`/`K`/`U`, Space flip, auto-advance, Accept remaining, the state copy table); recompute the CSP script hash.
  - `worker/` (new) — `worker/index.js` (one `POST /token` route, ~20 lines: forwards `code` and `code_verifier` plus the `GITHUB_CLIENT_SECRET` binding to GitHub, returns JSON) and `worker/wrangler.toml` serving `lib/snap_diff/review/` as static assets.
  - `.github/actions/upload-screenshots/action.yml` — new `review-url` input; when set and the PR is from this repository, the PR comment and job summary carry `Review N screenshots →` linking to `<review-url>/#/<repo>/pull/<n>?run=<run_id>`; remove the "To accept: …" hint.
  - `lib/snap_diff/reporters/html.rb`, `lib/snap_diff/reporters/templates/report.html.erb` — remove the review controls, `report_data`/`review` and the issue-URL builder; keep the manifest (with `sha256`); add one header link when `review-url` is known.
  - Delete `.github/actions/accept-screenshots/`, `.github/workflows/snap-diff-accept.yml`, `test/unit/accept_screenshots_test.rb`, `test/integration/review_controls_test.rb`.
  - `docs/ci-integration.md`, `CHANGELOG.md` — replace the comment/issue flow section with the review page section.
- **Dependencies**: none in the gem. The Worker uses only the Workers runtime; `wrangler` is run via `npx`.
- **Patterns to follow**: the earlier page's security model and its tests (`test/integration/review_page_test.rb`, `test/unit/review_page_csp_test.rb`, `test/support/fake_github_api.rb` at `f797a96`), extended with a fake `/token` endpoint; one inline script under a CSP `sha256` hash; DOM built with `textContent` only.
- **Patterns to avoid**: storing tokens in `localStorage` or cookies; any shared hosted instance; force-pushes; writing outside the manifest's paths; trusting artifact contents beyond the manifest entries and the requested files' bytes.
- **Configuration**: Worker secret `GITHUB_CLIENT_SECRET`, Worker variable `GITHUB_CLIENT_ID`; action input `review-url`.
- **Migration steps**: one PR replaces the comment/issue bot; nothing has shipped in a release, so no user migration is needed.

### Verification

- [ ] The spike shows a GitHub App user token can download a private repository's artifact, push a commit that starts CI, and sign in under SAML; results recorded below.
- [ ] Browser tests cover: sign-in redirect and `/token` exchange (fake), accept-then-commit (blob bytes equal the artifact's, ref updated without force, one PR comment naming accepted and rejected files), a moved branch refused, a malicious manifest refused, an expired artifact message.
- [ ] `test/unit/review_page_csp_test.rb` passes with the recomputed hash.
- [ ] No `localStorage`, `sessionStorage` token writes or cookies in `lib/snap_diff/review/index.html` (decisions may use `sessionStorage`).
- [ ] `.github/actions/accept-screenshots/` and `.github/workflows/snap-diff-accept.yml` no longer exist; `rake test:unit` and `actionlint` pass.
- [ ] End to end on a private repository: a failing PR's comment links to the page; after sign-in and Commit, the committed files' SHA-256 equal the artifact's, CI re-runs, and the rejected files are listed on the PR.

## Pros and Cons of the Options

### Personal-access-token review page on GitHub Pages

Built and proven on PR #314 (commits `7c8de1f`…`f797a96`).

- Good, because no server is needed.
- Bad, because the reviewer pastes a token on every visit ("very unfriendly").
- Bad, because a token held on the shared `<owner>.github.io` origin is readable by any other page there.
- Bad, because free Pages sites cannot restrict access, which leaks the page's existence for private repositories.

### PR comment or prefilled issue carried out by an Actions bot

Built on this branch (commits `d19dbf8`…`5d38a7e`), with a permission-API gate, run-to-PR binding, per-file hash binding and a lease push.

- Good, because no token and no infrastructure; the repository's `GITHUB_TOKEN` does the write.
- Bad, because the reviewer copies and pastes a command, or goes through a separate issue page ("too complicated").
- Bad, because `issue_comment`/`issues` workflows run only from the default branch, so nothing can be tried before merge.

### Self-hosted GitHub App + Cloudflare Worker + sign-in review page

- Good, because one sign-in then clicks; private repositories work; per-user permissions and identity; no third party.
- Bad, because adopters need a Cloudflare account and a GitHub App (automated by the setup ADR).

### Shared hosted GitHub App + Worker run by the gem maintainers

- Good, because adopter setup is two steps (install the app, add one action input).
- Bad, because a compromise of the hosted page or the maintainers' accounts would give write access to every signed-in reviewer's repositories for up to 8 hours; this is the first thing a company security review blocks.
- Bad, because the maintainers would run an open-ended service (secret rotation, outages, vendor questionnaires).

### Signed review links with a server-held repository credential

- Good, because reviewers would not sign in.
- Bad, because a signed link becomes a bearer write capability for anyone who sees it, with no per-user permission check or identity.
- Bad, because deploy keys are SSH-only and cannot use the Git Data API; a bot token would make the server a powerful credential holder.

### The PR's "Files changed" tab as the review UI

- Good, because GitHub already renders image diffs and approval is the normal PR review.
- Bad, because there is no per-screenshot choice before something is committed.

### A local command-line reviewer

- Good, because it uses the developer's existing git and `gh` login.
- Bad, because it is not a page; designers and product reviewers cannot use it.

## More Information

- Shape Up pitch and evidence (product, design, engineering seats; cold-eyes review): kept with this branch's working notes; the pitch's fat-marker sketch of the review screen and the state copy table are the design reference.
- Related: [Ship review setup as a gem executable](2026-10-23-ship-review-setup-as-a-gem-executable.md).
- Out of scope (no-gos): fork PRs, GitHub Enterprise Server, mobile layouts, a shared hosted instance.
- Revisit if: the spike fails for SAML organisations; GitHub ships CORS on its OAuth endpoints (the Worker could then go); or adopters ask for a shared instance for public repositories only.
