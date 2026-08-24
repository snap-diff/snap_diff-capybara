# Competitive landscape — observations for ideation

Durable record of what other tools do and why. Kept **out of `docs/`** on purpose:
`docs/` is packaged into the gem, and users do not want our competitor notes.

Everything below was **executed on a real machine** unless marked *(read)*.
Versions: Playwright 1.62.1 · Jest 30 · insta 1.48.0 · VCR 6.4.0 / WebMock 3.26.2
· SimpleCov 1.1.1 · RuboCop 1.89.0 · RSpec 3.13. Dated 2026-08-24.

---

## The two moments that decide a visual-testing tool

Everything here is organised around them, because our own customer research
found both broken:

- **M1 — the miss.** A green bar on a page that changed. Kills trust permanently.
- **M2 — the accept.** "This change is intentional, take the new picture." The
  most frequent daily action, forever.

Two more surfaced during the research:
- **M3 — the stale baseline.** A baseline no test references. Nobody tells you.
- **M4 — the silent skip.** Any path where the tool did not actually compare.

---

## Per tool

### Playwright `toHaveScreenshot` — the DevX benchmark

**Behaviour.** Four update modes: `missing` (default — writes an absent baseline
**and still fails**), `changed` (bare `-u`), `all`, `none`. Measured exit codes:

| mode | first run | 51st screenshot | exit |
|---|---|---|---|
| default `missing` | writes baseline, **fails** | writes, fails | 1 |
| `none` | writes nothing, fails | writes nothing, fails | 1 |
| `changed` / `all` | writes, **passes** | writes, passes | 0 |

**Pros.** Record-and-fail is the only model where the failure carries its own
fix — the next action is re-running the same command, so it costs zero new
knowledge. Baselines are named `{test}-{browser}-{platform}.png`, which makes
mac-vs-Linux mismatch *structurally impossible* rather than tribal knowledge.
Labelled, relative, ordered failure paths (`Expected:` / `Received:` / `Diff:`),
and `Diff:` is omitted when there is none — the block is honest about what exists.
Four HTML-report view modes; the **Slider** (drag a wipe line across both images)
is what people actually use to judge intent. `--only-changed [ref]` is git-native
("Only supports Git" is stated as *their* limitation; it is our premise).

**Cons.** The failure text contains **no instruction** — fine only because
"run it again" is the right move. `--update-snapshots=none` prints one character
less and re-running does **not** fix it: a genuine dead end, the worst message in
the set. No third status: a freshly recorded baseline is machine-indistinguishable
from a real regression in the JSON reporter (`status=failed`, `unexpected: 1`).
Writes baselines into CI workspaces that then evaporate — pure waste. Record-and-fail
also interacts badly with `retries: 1`: the re-run passes, so it reads as flake
(maintainer confirms in playwright#38046).

**Steal:** the mode ladder's *semantics*, labelled paths, platform-in-filename,
the report's slider. **Don't steal:** the instruction-free message.

### Jest `toMatchSnapshot` — the environment split

**Behaviour.** Local: writes and **passes** (`3 snapshots written`, exit 0).
Under `--ci` *or* a detected `CI` env var: writes nothing and **fails**.

**Pros.** `Snapshots: 1 written, 2 passed, 3 total` — the only three-way status
line any of these tools produces in a *passing* run, and it costs one string.
Its CI message is the best sentence in the whole survey because it explains **why
this behaved differently from your laptop**: *"This is likely because this test is
run in a continuous integration (CI) environment in which snapshots are not
written by default."* No other tool answers that question, and it is the first
one every user asks.

**Cons.** Local `3 passed` with a brand-new snapshot nobody has looked at is a
green bar asserting something never checked — for a *binary* baseline no reviewer
will diff, that is worse than for JSON. The fix command (`-u`) differs from the run
command, so it must be learned: 3 commands to a trustworthy green vs Playwright's 2.
Env-detection has bitten them: for all of Jest 27, `CI=1 npx jest` wrote snapshots
and passed while `npx jest --ci` failed, because config read `argv.ci` rather than
detected state *(read: jest#12288)*.

**Steal:** the three-way count line, and the why-is-this-different sentence.

### Rust `insta` — the best middle state

**Behaviour.** Writes `.snap.new` beside `.snap` and fails (exit 101). Under
`CI=true`, writes nothing and drops exactly one line — the review hint, because
there is nothing to review.

**Pros.** "Recorded but not verified" is a **first-class, queryable, reviewable**
state, not a line of text: `cargo insta pending-snapshots` lists them,
`accept`/`reject` resolve them. `--unreferenced=warn|reject|delete` solves M3 in
the same tool. `cargo insta test --accept` is a one-command path. The failure text
names the exact command, inside the failure body, next to the diff — the best
instruction of the four. CLI flags take precedence over the `CI` env var, deliberately
narrowed after Ruff hit the opposite *(read: insta#924)* — **normally CLI flags
outrank environment variables**, and our current default has the inverse shape.

**Cons.** Requires a companion binary (`cargo-insta`). The two-file dance is more
machinery than a screenshot gem may want.

**Steal:** pending-state as a queryable thing; `--unreferenced`; explicit-outranks-env.

### VCR (Ruby) — the closest precedent we have

**Behaviour.** Record modes are **Ruby config**, not CLI flags:
`:once` (default) records when the cassette is absent and passes — but **raises**
when something new appears in an existing cassette. `:none` raises on anything
missing. Also `:new_episodes`, `:all`.

**Pros.** `:once` already implements the compromise everyone else is groping
toward: *bootstrapping is fine; adding to an established recording is not.* The
error message is the best-designed in Ruby: it **restates the effective config
back at you** (`:record => :none`, `:match_requests_on => [...]`), enumerates every
escape route *including "if you're surprised, here's how to debug"*, and uses
**versioned doc links** (`?v=6-4-0`) that can never point at docs for an API you
do not have. Being config-shaped, it is the proof that a mode ladder does **not**
need a test runner to hang a flag on.

**Cons.** The `:once` recovery advice is *"delete the cassette file and re-run"* —
i.e. throw away 50 good recordings to add the 51st. No CLI switch, so changing
mode is an edit-run-revert cycle. 22 lines of stack trace after the message.

**Steal:** config-shaped record modes; restating effective config in errors;
versioned doc links. **Don't steal:** delete-everything recovery advice.

### WebMock (Ruby) — errors that emit the fix

Prints the literal `stub_request(...)` snippet, pre-filled with the request it
just saw. **Generated from live state, so it cannot drift.** This is the antidote
to how `RECORD_SCREENSHOTS=1` rotted in our own error message for years.

> **Rule: never print a command in an error message that is not generated from live state.**

### SimpleCov (Ruby) — the closest analog for report + threshold

Four lines, each earning its place: what it is, what was required, **where to look
first** (lowest-coverage files), and how the process ended — with a **distinct exit
code 2** for "the tool ran fine, your content failed the gate", separable from a crash.

**Steal:** the four-line shape; a distinct exit code for gate-failure.

### RuboCop / Standard — bulk-accept with a built-in exit plan

`--auto-gen-config` writes `.rubocop_todo.yml`; `.rubocop.yml` becomes one line.
The todo file **states its own expiry condition** ("The point is for the user to
remove these configuration records one by one") and carries `# Offense count: N`
per entry — the size of what was swallowed. Plain output marks fixables inline
and totals them (`16 offenses autocorrectable`), so users learn `-a` exists **by
reading a failure**, not docs.

**Steal:** the count line that teaches the fix command; accepted-state-as-debt framing.
**Don't steal:** a `.snap_diff_todo.yml` — our accepted state is already PNGs in git,
which is more reviewable than a YAML exclusion list.

### RSpec — failure output as the signature feature

`example_status_persistence_file_path` is a human-readable table;
`--only-failures` and `--next-failure` read it. Ruby-native precedent our users
already know, and the model behind "re-run only what failed, then accept it".

### Percy — the anti-lesson, from the category leader

```
$ npx @percy/cli exec -- echo hi
[percy] Skipping visual tests
[percy] Error: Missing Percy token
$ echo $? → 0
```

Prints the word `Error`, says it is skipping every visual test, and **exits 0**.
A CI job that loses its token goes green forever — **M1 shipped at scale**.
Approval is server state (`build:approve <build-id>`), and their "Visual Git"
explicitly *"does not rely on Git commit information"* — the opposite of our premise.

> **Rule: misconfiguration must be a non-zero exit.**

### Chromatic — every unearned green needs a name

`--auto-accept-changes [branch]`, `--exit-zero-on-changes [branch]`, `--skip [branch]`,
`--ignore-last-build-on-branch`. **Every route to a green bar without a real
comparison has its own flag, name, and branch scope.** You cannot land there by
accident, and a reviewer reading CI config sees it. This is the cure for M4.

### jest-image-snapshot — stale-baseline detection

`OutdatedSnapshotReporter`: append every touched baseline path during the run,
set-difference at the end. Opt-in, and the README is candid about why:
*"Do not run a partial test suite with this flag as it may consider snapshots of
tests that weren't run to be obsolete."* **Obsolescence is only knowable from a
full run** — so the correct first version reports, never deletes. Also embeds diff
images in iTerm2 via escape codes: charming, two config options and a terminal
allow-list, for something a labelled path does for everyone.

### Argos — naming the third state

Until a build has run on the default branch, PR builds are marked **orphan** — a
distinct, named, visible status. Not a pass, not a failure. The conceptual fix for M1.

### Where we looked and found nothing

Applitools (no CLI text obtainable without an account) · `percy-capybara`
specifically (nothing Capybara-specific worth quoting) · Lost Pixel's user-facing
messages · Reddit/HN first-run-friction complaints (they live in issue trackers,
not forums) · a Rails/rubyonrails stance on missing fixtures.

---

## Defaults: who fails on a missing baseline

The single most useful table here, because it decided a live argument.

| Tool | local | CI | writes it? | changed over time? |
|---|---|---|---|---|
| Playwright | **FAIL** | **FAIL** | yes | never had a pass default |
| Jest | pass | **FAIL** | not on CI | **yes** — Jest 20, 2017 |
| jest-image-snapshot | pass | **FAIL** | not on CI | inherits Jest |
| Vitest | pass | **FAIL** | not on CI | **yes** |
| AVA | pass | **FAIL** | not on CI | **yes** — 2.0.0, breaking change |
| testthat (R) | pass + warn | **FAIL** | **writes then fails** | **yes** — 3.3.0, Nov 2025 |
| insta | **FAIL** | **FAIL** | `.snap.new` only | no |
| syrupy (Py) | **FAIL** | **FAIL** | no | no, by design |
| ApprovalTests / `approvals` (Ruby) | **FAIL** | **FAIL** | `.received` only | no |
| **rspec-snapshot (Ruby)** | pass | **pass** | yes | no — request open 3½ years |
| VCR `:once` (Ruby) | pass | pass | yes | no |

**The consensus is CI-only failure.** Playwright is the sole always-fail and is
greenfield with no migration to perform. A tool that flipped this default and
*reverted* does not exist — searched, found none. The nearest things: testthat
shipped it after a **four-year** deliberation and already has an open request to
disable it from a maintainer with many visual snapshots; insta narrowed its CI
override; a downstream broke because it relied on "new screenshot never fails".

**Screenshots are not text snapshots.** A locally-generated screenshot baseline is
often worthless — Playwright stamps `-darwin` into filenames precisely because
fonts and antialiasing differ across OS. So "fail locally so the developer records
one" produces a baseline that fails CI anyway. This is why we did **not** flip.

**Migration precedent, four data points, consistent:** major version documented as
breaking (AVA), or minor but CI-gated only (Jest, testthat), a named user-settable
knob rather than an env var, and **ship the retrieval path in the same release** —
testthat added `snapshot_download_gh()` alongside, because "CI wrote the baseline
then failed" is unactionable when the artifact dies with the runner. Nobody used a
deprecation cycle or a legacy mode.

---

## Ideas parked, with the reason (do not re-propose without new evidence)

- **Approval UI / dashboards** (Percy, Chromatic, Argos, Applitools) — need a
  service and a build database. Out of model. The local equivalent of "approve"
  is `git add` of a file the tool just regenerated, and it is *better* for review:
  a diff, not a database row.
- **TurboSnap-style dependency tracing** — four flags to configure one feature.
  The cheap version is "only run tests whose baseline or test file changed vs main".
- **Terminal image embedding** — works for some users on some terminals.
- **`.snap_diff_todo.yml`** — our accepted state is already PNGs in git.
- **RBS/Sorbet** — freezes an interface we are actively shrinking.
