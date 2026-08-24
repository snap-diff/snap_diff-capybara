# Snapshot and visual-regression tools — reference

Factual reference on how these tools behave. No recommendations; conclusions
drawn for this project live in the ADRs.

Kept out of `docs/` because `docs/` is packaged into the gem.

**Observed 2026-08-24.** Versions: Playwright 1.62.1 · Jest 30 · insta 1.48.0 +
cargo-insta 1.48.0 · VCR 6.4.0 · WebMock 3.26.2 · SimpleCov 1.1.1 · RuboCop
1.89.0 · RSpec 3.13 · activesupport 8.1.3.1.

### How the measurements were taken

Every `(measured)` row is verbatim stdout/stderr from a command run on **one
machine**: macOS on Apple silicon, retina display, versions as listed above. Each
ran once unless the row says otherwise. `(source)` rows were read from the tool's
own code, `--help`, docs, or issue tracker at the URL in Sources.

**What one run proves.** Exit codes and message text are deterministic given a
fixed version and fixture, so a single run is adequate evidence for those.
Timings, seeds and timestamps are not properties of the tool and appear only
because output is quoted verbatim — specifically `2 passed (541ms)`,
`--seed 22661` (Minitest re-randomises per run), `0.00914 seconds` in the RSpec
table, and the `2026-08-24 06:52:30 UTC` stamp in the RuboCop header.

**The `-darwin` suffix is this machine, not a constant.** `alpha-darwin.png` and
`example-1-chromium-darwin.png` carry the platform token of the host that ran
them; on Linux the same baselines are `-linux`. That is Playwright's naming
scheme working, not an artifact of the transcript.

**Retina did not distort the figures**, because none of the quoted numbers are
pixel dimensions, and because Playwright's `toHaveScreenshot` defaults to
`scale: "css"` — screenshots normalise to CSS pixels, so a 2x display does not
double baseline dimensions. Any future measurement reporting image dimensions,
file sizes or diff-pixel counts must state the device pixel ratio.

**Fixture-dependent numbers are not tool properties.**
`1 file inspected, 19 offenses detected` and `Line coverage: 6 / 12 (50.00%)`
describe throwaway fixtures, not RuboCop or SimpleCov. They illustrate output
*shape*; the counts carry no information.

**Not recorded at the time, therefore unknown:** which runner the Ruby
measurements used (`activesupport 8.1.3.1` appears in the version list but
nowhere in the body), whether anything beyond the tools' own stubbing was in
place for the VCR and WebMock runs, and whether the Playwright project drove a
real browser. A re-measurement should capture these.

Note that **SimpleCov 1.1.1 was released 2026-08-12**, twelve days before these
observations — that row describes a then-new release.

### Scope and selection

Three overlapping groups, chosen deliberately and **not sampled**: (a) image-based
visual-regression tools (Playwright, jest-image-snapshot, BackstopJS, Lost Pixel,
Percy, Chromatic, Argos, Applitools); (b) value-snapshot libraries across
languages, chosen for ecosystem spread rather than popularity (Jest, Vitest, AVA,
insta, syrupy, pytest-regressions, cupaloy, testthat, ApprovalTests,
rspec-snapshot); (c) Ruby tools that are *not* snapshot tools but solve the
adjacent "record on first run" or "gate a build" problem (VCR, WebMock, SimpleCov,
RuboCop, RSpec, Minitest), included because Ruby conventions are relevant to a
Ruby reader.

**Known exclusions.** No commercial tool was exercised beyond its free CLI
surface; Applitools was excluded for want of an account. Storybook's test-runner,
Loki, reg-suit, Wraith, Galen and Cypress image plugins were not examined.
Nothing was excluded for behaving in a particular way.

**Any third-party usage observation would come from GitHub code search over
public repositories, which is a biased sample** — it sees only public, indexed
and, through result ranking and caps, disproportionately popular repositories.
Counts from it are lower bounds on public usage, not estimates of usage overall.

---

## Scope of this reference

This document concentrates on **first-run and missing-baseline behaviour**, and
on how each tool is configured and what it prints. That emphasis is a choice of
the author, not a claim about what matters most in the field. Areas deliberately
not covered are listed at the end.

## 1. Behaviour on a missing baseline

Sorted by ecosystem, then alphabetically.

| Tool | Local | CI | Writes the artifact? | Default changed over time? |
|---|---|---|---|---|
| Playwright `toHaveScreenshot` | fail | fail | yes | no |
| Jest `toMatchSnapshot` | pass | fail | not on CI | yes (jest#3456) |
| jest-image-snapshot | pass | fail | not on CI | inherits Jest |
| Vitest | pass | fail | not on CI | yes (vitest#3227) |
| AVA | pass | fail | not on CI | yes (2.0.0) |
| testthat (R) | pass + warning | fail | writes, then fails | yes (3.3.0) |
| insta (Rust) | fail | fail | `.snap.new` only, not on CI | no |
| syrupy (Python) | fail | fail | no | no |
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

No tool was found that adopted fail-on-missing and later reverted it. Search
scope: changelogs and issue trackers for Playwright, Jest, Vitest, AVA, testthat,
insta, syrupy and jest-image-snapshot, as of 2026-08-24. **The observation window
is short for the only recent adopter** — testthat 3.3.0 shipped roughly nine
months before this was written, so its absence of a reversal carries little
weight.

Subsequent activity on that change, described without adjudicating whether it
constitutes a reversal: testthat#2293 added a `fail_on_new == FALSE` code path
after a downstream package (`shinytest2`) broke; testthat#2320 (open) requests
that the default be configurable; insta#924 narrowed its CI override so explicit
flags take precedence over the `CI` environment variable.

---

## 2. Per tool

### Playwright — `toHaveScreenshot`

**Update modes** (source, `--help`): `-u, --update-snapshots [mode]`, choices
`all`, `changed`, `missing`, `none`. No flag defaults to `missing`; a bare `-u`
means `changed`. These modes are **not listed on the visual-comparison guide
page** (playwright.dev/docs/test-snapshots, checked 2026-08-24); CLI `--help` was
the only observed source.

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
of 2026-04-07.

---

## 2b. Tolerance and anti-aliasing configuration

| Tool | Knobs | Defaults | Noise handling |
|---|---|---|---|
| Playwright `toHaveScreenshot` | `threshold`, `maxDiffPixels`, `maxDiffPixelRatio` | `threshold` 0.2 (YIQ colour space); the other two unset | `animations: "disabled"`, `caret: "hide"`, `scale: "css"` by default; `mask` overlays locators; `stylePath` injects CSS |
| jest-image-snapshot | `failureThreshold`, `failureThresholdType`, `comparisonMethod`, `customDiffConfig.threshold`, `blur`, `allowSizeMismatch` | `failureThreshold` 0, type `pixel`, method `pixelmatch`, pixelmatch `threshold` 0.01, `blur` 0, `allowSizeMismatch` false | `blur` (Gaussian, px) for cross-resolution scaling noise; `ssim` as an alternative to per-pixel comparison |

Both default to **pixelmatch**. Note that Playwright's `threshold` and
jest-image-snapshot's `customDiffConfig.threshold` are the *same pixelmatch
parameter* with defaults a factor of twenty apart — 0.2 against 0.01.

Sources: [PageAssertions](https://playwright.dev/docs/api/class-pageassertions#page-assertions-to-have-screenshot-1) ·
[jest-image-snapshot](https://github.com/americanexpress/jest-image-snapshot).

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

insta surfaces failures as `cargo test` panics; **101 is Rust's panic exit code**
and does not vary by situation, so its column carries no information beyond
"failed".

Percy exits 0 when no token is configured. Per their documentation this is
deliberate, so that forks and PRs without access to repository secrets do not
fail the build.

**Distribution of platform-specific baselines.** Playwright encodes browser and
platform in the filename by default. jest-image-snapshot, BackstopJS and
rspec-snapshot do not.

---

## 4. History of default changes

Four tools changed their missing-baseline behaviour after release:

| Tool | Release | Change | Notes |
|---|---|---|---|
| Jest | 20 (2017) | stopped writing snapshots on CI | jest#3456 |
| AVA | 2.0.0 (2019) | fails on CI when no snapshot found | listed under "Breaking changes" |
| Vitest | — | fails on CI rather than writing | vitest#3227 |
| testthat | 3.3.0 | fails when creating a new snapshot on CI | `snapshot_download_gh()` added in the same release, for retrieving snapshots written by CI |

In all four the change applied to CI only; local behaviour was unchanged. None
used a deprecation cycle or a legacy mode. Each exposes a named user-settable
option (`--ci` / `updateSnapshot`, `fail_on_new`) alongside environment detection.

The testthat 3.3.0 release date is not given in `NEWS.md` and was not confirmed;
the CRAN package page lists only the current version.

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
- **testthat 3.3.0 / 3.3.1 release dates** — absent from `NEWS.md` and from the
  CRAN package page; obtainable only from the CRAN Archive listing, not fetched.
- **Cost** — not researched. Percy, Chromatic, Argos and Applitools price per
  snapshot or screenshot with tiers that change frequently; no figures captured
  and none should be inferred from this document.
- **Second and subsequent failures of the same baseline** — not exercised for any
  tool. Whether output, exit code or artifact naming differs on a repeat failure
  is unknown.
- **Colour-blind accessibility of diff artefacts** — not assessed. No tool's diff
  rendering was checked against a deuteranopia or protanopia simulation, and none
  surveyed was observed documenting a colour-blind-safe palette.
- **Baseline storage growth over time** — not measured for any tool.
- **Tolerance/anti-aliasing for tools other than Playwright and
  jest-image-snapshot** — not gathered.

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
