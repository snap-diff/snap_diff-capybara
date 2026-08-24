# Snapshot and visual-regression tools — reference

Factual reference on how these tools behave. No recommendations; conclusions
drawn for this project live in the ADRs.

Kept out of `docs/` because `docs/` is packaged into the gem.

**Observed 2026-08-24.** Versions: Playwright 1.62.1 · Jest 30 · insta 1.48.0 +
cargo-insta 1.48.0 · VCR 6.4.0 · WebMock 3.26.2 · SimpleCov 1.1.1 · RuboCop
1.89.0 · RSpec 3.13 · activesupport 8.1.3.1.

Rows marked **(measured)** were executed locally and the output is verbatim.
Rows marked **(source)** were read from the tool's code, docs, or issue tracker.

---

## 1. Behaviour on a missing baseline

The defining question for a snapshot tool: what happens when there is nothing to
compare against.

| Tool | Local | CI | Writes the artifact? | Default changed over time? |
|---|---|---|---|---|
| Playwright `toHaveScreenshot` | fail | fail | yes | no — never had a passing default |
| Jest `toMatchSnapshot` | pass | fail | not on CI | yes — Jest 20, 2017 (source: jest#3456) |
| jest-image-snapshot | pass | fail | not on CI | inherits Jest |
| Vitest | pass | fail | not on CI | yes (source: vitest#3227) |
| AVA | pass | fail | not on CI | yes — 2.0.0, documented breaking change |
| testthat (R) | pass + warning | fail | writes, then fails | yes — 3.3.0, 2025-11-13 |
| insta (Rust) | fail | fail | `.snap.new` only, not on CI | no |
| syrupy (Python) | fail | fail | no | no — designed so |
| pytest-regressions | fail | fail | yes | no |
| ApprovalTests / `approvals` (Ruby) | fail | fail | `.received` only | no |
| cupaloy (Go) | fail | fail | no | no |
| rspec-snapshot (Ruby) | pass | pass | yes | no |
| VCR `:once` (Ruby) | pass | pass | yes | no |
| VCR `:none` (Ruby) | raise | raise | no | no |
| Applitools Eyes | varies by SDK | varies | server-side | `saveNewTests` defaults true in Cypress/Protractor SDKs, false in the Playwright SDK |
| Percy | n/a | first build auto-approved on default branch | server-side | — |
| Chromatic | n/a | new story = change requiring approval | server-side | — |

CI detection is by environment variable in Jest, AVA, Vitest, insta and testthat.
Playwright and syrupy do not vary by environment.

**No tool was found that adopted fail-on-missing and later reverted it.**
Searched changelogs and issue trackers for Playwright, Jest, Vitest, AVA,
testthat, insta, syrupy and jest-image-snapshot. Related but not reversals:
testthat has an open request to make it configurable (testthat#2320, opened
2026-02-03); insta narrowed its CI override so explicit flags win (insta#924);
testthat added a `fail_on_new = FALSE` path after a downstream broke
(testthat#2293).

---

## 2. Per tool

### Playwright — `toHaveScreenshot`

**Update modes** (source, `--help`): `-u, --update-snapshots [mode]`, choices
`all`, `changed`, `missing`, `none`. No flag defaults to `missing`; a bare `-u`
means `changed`.

**(measured)** Exit codes, one missing baseline among two passing:

| mode | baseline written | exit |
|---|---|---|
| default (`missing`) | yes | 1 |
| `none` | no | 1 |
| `changed` | yes | 0 |
| `all` | yes | 0 |

**(measured)** First run, no baselines:
```
Error: A snapshot doesn't exist at /…/alpha-darwin.png, writing actual.
  2 failed
```
Second run, unchanged: `2 passed (541ms)`. Under `none` the message is
`A snapshot doesn't exist at /…/gamma-darwin.png.` — no trailing clause, and
re-running does not resolve it.

**(source)** `toMatchSnapshot.ts:198` builds that message; `:211` returns a
literal `false`, so the file is written on the same run the test fails.

**Failure output (measured):** paths are relative to project root, labelled and
ordered — `Expected:` / `Received:` / `Diff:`. `Diff:` is absent when no diff
exists.

**Baseline naming (source):** `{testName}-{browser}-{platform}.png`, e.g.
`example-1-chromium-darwin.png`, in `{testFile}-snapshots/`. Rationale given in
docs and issue #22337: rendering differs across operating systems.

**Status model (measured):** the JSON reporter reports a newly recorded baseline
as `status=failed`, `unexpected: 1` — identical to a real difference. No separate
state.

**Retries (source, playwright#38046):** a maintainer states that missing-baseline
failures are deliberately not retried, because a retry would pass and the run
would be reported as flaky.

**Other:** `--only-changed [ref]` runs only test files changed vs a git ref
("Only supports Git"). HTML report offers four view modes — Diff, Actual, Side by
side, Slider (`imageDiffView.tsx:103-113`).

### Jest — `toMatchSnapshot`

**(measured)** Local, fresh project: `› 2 snapshots written`, `Tests: 2 passed`,
exit 0. New test added to a passing suite:
`Snapshots: 1 written, 2 passed, 3 total`, exit 0.

**(measured)** With `--ci`, or with `CI=true` and no flag:
```
New snapshot was not written. The update flag must be explicitly passed to write a new snapshot.

This is likely because this test is run in a continuous integration (CI) environment in which snapshots are not written by default.
```
`Tests: 3 failed`, exit 1. Summary line: `Inspect your code changes or re-run
jest with '-u' to update them.`

**(source)** `--help`: "`--ci` … This option is on by default in most popular CI
environments. It will prevent snapshots from being written unless explicitly
requested." Docs state the rationale: "since new snapshots automatically pass,
they should not pass a test run on a CI system."

**Status line:** `Snapshots: N written, N passed, N total` — three states on one
line, in passing runs.

**(source, jest#12288)** Throughout Jest 27, `CI=1 npx jest` wrote snapshots and
passed while `npx jest --ci` failed: the config consulted `argv.ci` rather than
detected CI state. Fixed in Jest 28.

### insta (Rust)

**(measured)** Plain `cargo test`, no snapshots: writes
`…__alpha_renders.snap.new`, test FAILED, exit 101. Failure body ends
`To update snapshots run 'cargo insta review'`.

**(measured)** `cargo insta pending-snapshots` lists awaiting files with
per-snapshot `review` / `accept` / `reject` commands. `cargo insta accept`
resolves them; `cargo insta test --accept` is a single-command path.

**(measured)** Under `CI=true`: no `.snap.new` written, and the review hint line
is omitted. Everything else identical.

**(measured)** `--unreferenced=warn|reject|delete` detects baselines no test
references: `warn` exits 0 with a list, `reject` exits 1, `delete` removes them.

**(source, insta#924, 1.48.0)** `CI=true` normally implies `--check`; explicit
options such as `--accept` now take precedence. Reported from Ruff, on the
principle that CLI flags outrank environment variables.

### VCR (Ruby)

**Record modes (source):** `:once` (default), `:none`, `:new_episodes`, `:all`.
Set in Ruby — `VCR.use_cassette("x", record: :none)` or
`config.default_cassette_options` — not via CLI.

**(measured)** `:once`, no cassette: records, exit 0, no output. `:once` with an
existing cassette and a new interaction: raises. `:none`, missing cassette: raises.

**(measured)** The `:none` error:
```
An HTTP request has been made that VCR does not know how to handle:
  GET http://example.com/

VCR is currently using the following cassette:
  - /…/cassettes/brand_new.yml
    - :record => :none
    - :match_requests_on => [:method, :uri]

Under the current configuration VCR can not find a suitable HTTP interaction
to replay and is prevented from recording new requests. There are a few ways
you can deal with this:

  * If you're surprised VCR is raising this error
    and want insight about how VCR attempted to handle the request,
    you can use the debug_logger configuration option to log more details [1].
  * You can use the :new_episodes record mode to allow VCR to
    record this new request to the existing cassette [2].
  * If you want VCR to ignore this request (and others like it), you can
    set an `ignore_request` callback [3].
  * The current record mode (:none) does not allow requests to be recorded. …

[1] https://benoittgt.github.io/vcr/?v=6-4-0#/configuration/debug_logging
[2] https://benoittgt.github.io/vcr/?v=6-4-0#/record_modes/new_episodes
[3] https://benoittgt.github.io/vcr/?v=6-4-0#/configuration/ignore_request
[4] https://benoittgt.github.io/vcr/?v=6-4-0#/record_modes/none
```
Followed by ~22 lines of stack trace. Doc links carry the version (`?v=6-4-0`).
The message restates the cassette's effective configuration.

Under `:once` the final bullet differs: "You can delete the cassette file and
re-run your tests to allow the cassette to be recorded with this request."

### WebMock (Ruby)

**(measured)** On an unregistered request, prints a ready-to-paste stub built
from the observed request:
```
You can stub this request with the following snippet:

stub_request(:post, "http://example.com/api/users").
  with(
    body: "{\"name\":\"bob\"}",
    headers: { 'Content-Type'=>'application/json', 'Host'=>'example.com' }).
  to_return(status: 200, body: "", headers: {})
```

### SimpleCov (Ruby)

**(measured)** With `minimum_coverage line: 90` and 50% actual:
```
Coverage report generated for RSpec to coverage/index.html
Line coverage: 6 / 12 (50.00%)
Line coverage (50.00%) is below the expected minimum coverage (90.00%).
  Lowest-coverage files (line):
     50.00%  lib/thing.rb
SimpleCov failed with exit 2 due to a coverage related error
```
Exit code **2**, distinct from 1. Source: `exit_codes/minimum_overall_coverage_check.rb:25,:37`.

### RuboCop / Standard

**(measured)** `rubocop --auto-gen-config` writes `.rubocop_todo.yml` and adds
`inherit_from:` to `.rubocop.yml`. Generated file header:
```
# This configuration was generated by `rubocop --auto-gen-config`
# on 2026-08-24 06:52:30 UTC using RuboCop version 1.89.0.
# The point is for the user to remove these configuration records
# one by one as the offenses are removed from the code base.

# Offense count: 1
# This cop supports safe autocorrection (--autocorrect).
Layout/EmptyLineBetweenDefs:
  Exclude:
    - 'bad.rb'
```
Plain output marks correctable offences inline (`[Correctable]`) and totals them:
`1 file inspected, 19 offenses detected, 16 offenses autocorrectable`.

### RSpec

**(measured)** `example_status_persistence_file_path` writes a human-readable table:
```
example_id                | status | run_time        |
------------------------- | ------ | --------------- |
./spec2/demo_spec.rb[1:1] | failed | 0.00914 seconds |
```
Consumed by `--only-failures` and `--next-failure`. `--bisect` narrows
order-dependent failures.

### Minitest

**(measured)** Prints `Run options: --seed 22661` at the start of every run,
passing or failing.

### Percy

**(measured)** With no token:
```
$ npx @percy/cli exec -- echo hi
[percy] Skipping visual tests
[percy] Error: Missing Percy token
[percy] Command "echo hi" exited with status: 0
$ echo $?
0
```
**(source)** Approval is server-side and build-scoped: `build:approve <build-id>`,
`build:unapprove`, `build:reject`. Percy's "Visual Git" maintains per-branch
baselines and, per their docs, "does not rely on Git commit information".

### Chromatic

**(source, `--help`)**
```
--auto-accept-changes [branch]     If there are any changes to the build, automatically accept them. Only for [branch], if specified.
--exit-zero-on-changes [branch]    If all snapshots render but there are visual changes, exit with code 0 rather than the usual exit code 1.
--skip [branch]                    Skip Chromatic tests, but mark the commit as passing.
--ignore-last-build-on-branch <branch>   Do not use the last build on this branch as a baseline if it is no longer in history (i.e. branch was rebased).
```
Each is separately named and branch-scopable. TurboSnap (dependency-traced
test selection) is configured via `--trace-changed`, `--untraced`, `--externals`,
`--storybook-base-dir`.

### jest-image-snapshot

**(source)** `OutdatedSnapshotReporter` appends every touched baseline path to
`.jest-image-snapshot-touched-files` during a run and set-differences at the end.
Gated on `JEST_IMAGE_SNAPSHOT_TRACK_OBSOLETE`. README states: "Do not run a
*partial* test suite with this flag as it may consider snapshots of tests that
weren't run to be obsolete." Also supports inline diff images in iTerm2/WezTerm
via terminal escape codes, gated on a terminal allow-list plus an env var.

### Argos

**(source)** Until a build has run on the default branch, PR builds are labelled
**orphan** — a status distinct from both pass and fail.

### testthat (R)

**(source)** 3.3.0 NEWS: "`expect_snapshot()` and friends will now fail when
creating a new snapshot on CI. This is usually a signal that you've forgotten to
run it locally before committing (#1461)." Issue #1461 was open 2021-09-28 →
2025-08-01. Implementation: `fail_on_new <- self$fail_on_new %||% on_ci()`; the
file variant copies the snapshot and *then* fails.

The same release added `snapshot_download_gh()` for retrieving snapshots written
by CI. 3.3.1 narrowed the hint to jobs named "R-CMD-check" (#2300).

Subsequent reports: #2293 — a downstream (`shinytest2`) relied on screenshot
snapshots never failing, resolved by adding a `fail_on_new == FALSE` path.
#2320 (open) requests configurability, arguing that a package with no committed
snapshots is bootstrapping rather than regressing, and proposing the default be
derived from whether a snapshot directory already exists.

### rspec-snapshot (Ruby)

**(source)** Creates the snapshot file and passes, in CI as well as locally.
Issue #32, "Tests pass in CI if no snapshot is found", opened 2022-10-18, open as
of 2026-04-07. Issue #38, "Project status?", also open.

---

## 3. Cross-cutting mechanisms

**Accept / update workflows**

| Tool | Mechanism | Re-runs the test? |
|---|---|---|
| Playwright | `--update-snapshots`, `--last-failed` | yes |
| Jest | `-u` / `--updateSnapshot` | yes |
| insta | `cargo insta review\|accept\|reject`, `test --accept` | `test --accept` does |
| BackstopJS | `backstop approve` (source: `approve.js`, copies `failed_diff_*` to reference), `--filter` | no — promotes artifacts |
| Lost Pixel | `update` mode via arg, `-m`, or `LOST_PIXEL_MODE` env | yes |
| RuboCop | `--auto-gen-config` (exclusion file), `-a` (fix source) | n/a |
| VCR | change record mode in source | yes |
| Percy / Chromatic / Argos | server-side approval UI | no |

**"Recorded but not verified" as a distinct state**

- insta: `.snap.new` file, `pending-snapshots` subcommand, suppressed under CI.
- Jest: a word in the summary — `N written` alongside `N passed`, `N failed`.
- Argos: a named build status, "orphan".
- Playwright: none — indistinguishable from a failure in the JSON reporter.

**Stale-baseline detection**

- insta: `--unreferenced=warn|reject|delete`.
- jest-image-snapshot: opt-in touched-file tracking, report only.
- Others surveyed: none found.

**Exit codes observed (measured)**

| Situation | Playwright | Jest | insta | VCR | SimpleCov |
|---|---|---|---|---|---|
| missing baseline, local | 1 | 0 | 101 | 0 (`:once`) / 1 (`:none`) | n/a |
| missing baseline, CI | 1 | 1 | 101 | same | n/a |
| gate failure | 1 | 1 | 101 | 1 | **2** |
| misconfiguration | 1 | 1 | 101 | 1 | 1 |

Percy exits 0 on missing configuration (see above).

**Distribution of platform-specific baselines.** Playwright encodes browser and
platform in the filename by default. jest-image-snapshot, BackstopJS and
rspec-snapshot do not. Third-party Capybara users of `capybara-screenshot-diff`
were observed setting an equivalent option manually (`add_os_path`).

---

## 4. Migration precedents for changing a default

Four cases where a snapshot tool changed its missing-baseline behaviour:

| Tool | Vehicle | Scope of change | Accompanying work |
|---|---|---|---|
| Jest 20 (2017) | feature release | CI only | — |
| AVA 2.0.0 (2019) | major, listed under "Breaking changes" | CI only | — |
| Vitest | feature release | CI only | — |
| testthat 3.3.0 (2025) | feature release | CI only | `snapshot_download_gh()` shipped in the same release |

None used a deprecation cycle, a warning period, or a legacy mode. All exposed a
named user-settable option (`--ci`/`updateSnapshot`, `fail_on_new`) rather than
relying solely on environment detection.

---

## 5. Not covered

- **Applitools** — CLI text and behaviour not obtainable without an account.
- **percy-capybara specifically** — the CLI it drives was exercised; nothing
  Capybara-specific was observed beyond the above.
- **Lost Pixel user-facing messages** — mode dispatch was read
  (`utils.ts:56-58`); no failure output captured.
- **factory_bot, Capybara's own matcher errors, RSpec `--bisect`** — not exercised.
- **Community discussion outside issue trackers** — searched Reddit and HN for
  first-run-friction reports; nothing citable found.
- **A Rails/rubyonrails position** on missing fixtures or baselines — searched,
  none found.

---

## Sources

Playwright: [TestConfig](https://playwright.dev/docs/api/class-testconfig) ·
[#38046](https://github.com/microsoft/playwright/issues/38046) ·
[#23090](https://github.com/microsoft/playwright/issues/23090) ·
[#22337](https://github.com/microsoft/playwright/issues/22337).
Jest: [#3456](https://github.com/jestjs/jest/pull/3456) ·
[#12288](https://github.com/jestjs/jest/issues/12288) ·
[snapshot docs](https://jestjs.io/docs/snapshot-testing).
jest-image-snapshot: [#281](https://github.com/americanexpress/jest-image-snapshot/issues/281).
Vitest: [#3227](https://github.com/vitest-dev/vitest/issues/3227) ·
[snapshot guide](https://vitest.dev/guide/snapshot).
AVA: [#1585](https://github.com/avajs/ava/issues/1585) ·
[2.0.0](https://github.com/avajs/ava/releases/tag/v2.0.0).
testthat: [NEWS](https://github.com/r-lib/testthat/blob/main/NEWS.md) ·
[#1461](https://github.com/r-lib/testthat/issues/1461) ·
[#2149](https://github.com/r-lib/testthat/pull/2149) ·
[#2293](https://github.com/r-lib/testthat/issues/2293) ·
[#2320](https://github.com/r-lib/testthat/issues/2320).
insta: [CHANGELOG](https://github.com/mitsuhiko/insta/blob/master/CHANGELOG.md) ·
[#924](https://github.com/mitsuhiko/insta/pull/924).
syrupy: [README](https://github.com/syrupy-project/syrupy/blob/main/README.md).
pytest-regressions: [overview](https://pytest-regressions.readthedocs.io/en/latest/overview.html).
cupaloy: [repo](https://github.com/bradleyjkemp/cupaloy).
ApprovalTests.Ruby: [repo](https://github.com/approvals/ApprovalTests.Ruby).
rspec-snapshot: [#32](https://github.com/levinmr/rspec-snapshot/issues/32).
VCR: [record modes](https://rspec.help/vcr/record-modes/) ·
[no_cassette](https://andrewmcodes.gitbook.io/vcr/cassettes/no_cassette).
Applitools: [advanced configuration](https://applitools.com/docs/eyes/playwright/api/advanced-configuration).
Percy: [approval workflow](https://www.browserstack.com/docs/percy/build-results/approval).
Chromatic: [branching and baselines](https://www.chromatic.com/docs/branching-and-baselines/).
