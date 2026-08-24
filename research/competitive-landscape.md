# Snapshot and visual-regression tools — reference

Factual reference on how these tools behave. No recommendations; conclusions
drawn for this project live in the ADRs.

Kept out of `docs/` because `docs/` is packaged into the gem.

**Observed 2026-08-24.** Versions: Playwright 1.62.1 · Jest 30 (30.4.2 for §3
and §4) · jest-image-snapshot 6.5.2 · insta 1.48.0 + cargo-insta 1.48.0 ·
syrupy 6.0.0 · BackstopJS 6.3.25 · Lost Pixel 3.22.0 ·
`@percy/playwright` 1.1.2 + `@percy/core` types as published with it ·
`@argos-ci/playwright` 7.4.6 · VCR 6.4.0 · WebMock 3.26.2 · SimpleCov 1.1.1 ·
RuboCop 1.89.0 · RSpec 3.13 (3.13.2 for §3 and §4) · rspec-snapshot 2.2.0 ·
approvals 0.1.7 · activesupport 8.1.3.1.
Runtimes for the §3/§4 measurements: Ruby 4.0.6, Node v26.7.0 with npm 12.0.2,
Python 3.14.7 with pytest 9.1.1, cargo 1.97.1.

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

### Additional caveats for §3 and §4

**Reports were read by driving them, not by eye.** Each local HTML report
(Playwright, BackstopJS, SimpleCov, RSpec's HTML formatter) was opened in
headless Chromium; the quoted labels are `innerText` of the live DOM, and the
layout descriptions come from full-page screenshots of the same render. Nothing
in §4 marked `(measured)` was inferred from a minified bundle.

**BackstopJS ran on a substituted engine, which is machine-specific.** Its
default `"engine": "puppeteer"` would not start here: the bundled Chrome
resolved but `spawn` failed with `Unknown system error -88`. Switching to
`"engine": "playwright"` — a supported value shipping in the same package —
produced the run quoted in §3 and §4. The report format, the scenario schema
and `backstop approve` are not engine-dependent, but **no claim here rests on
BackstopJS's default capture path having been exercised.**

**Where a report needed a failure to render, one was manufactured** by editing
a fixture page (a header colour, a heading string and one element width). The
resulting diff percentages — `11.474392361111112%`, `content: 99.17%`,
`4241 pixels` — are properties of that fixture, not of the tools, and are
quoted only because output is quoted verbatim.

**Three hosted products were not exercised.** Percy, Chromatic and Argos
appear in §3 and §4 from their published packages, type declarations and
documentation only. No account was used, no build was created, and no claim
about their interfaces was checked against a running instance.

**Two more `-darwin`-class caveats.** The BackstopJS bitmap names quoted in §3
carry viewport labels chosen in the config for this run (`phone`, `desktop`),
not defaults; and the Playwright snapshot paths in §3 lack the
`-chromium-darwin` token because that section's project sets a custom
`snapshotPathTemplate`, as noted there.

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

This document covers four things: **first-run and missing-baseline behaviour**
(§1–§2), **the code a developer writes at the call site** (§3), **the report
they read after a failure and the action that resolves it** (§4), and
cross-cutting mechanisms and history (§5–§6). That selection is a choice of the
author, not a claim about what matters most in the field. Areas deliberately
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
("Only supports Git"). The HTML report's image view is described in §4; it
offers five modes, not the four recorded in an earlier draft of this file.

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

## 3. The assertion DSL — what is written at the call site

Three layers per tool: the assertion itself, options passed at the call site,
and global configuration. **Ordered alphabetically by tool name**; the ordering
carries no other meaning.

Tools that have **no call-site DSL** are included here rather than omitted,
because operating as an external CLI over a config file is a design position,
not a gap: BackstopJS, Chromatic and Lost Pixel take no assertion in a test.

### ApprovalTests / `approvals` (Ruby) 0.1.7

**(measured)** The assertion is a **block**, inside an RSpec example:

```ruby
it "verifies a value with a block" do
  verify { { name: "bob", roles: %w[a b] } }
end
```

**(measured)** Call-site options: `format:` selects the writer and therefore
the file extension; `name:` / `namer:` override the derived name.

```ruby
verify(format: :json) { { name: "bob" } }
```

**(source)** Configuration — settings the gem registers on RSpec
(`lib/approvals/extensions/rspec.rb:6-12`):

```ruby
RSpec.configure do |c|
  c.approvals_path           = "spec/fixtures/approvals/"
  c.approvals_namer_class    = Approvals::Namers::DirectoryNamer
  c.diff_on_approval_failure = false
  c.approvals_default_format = nil
end
```

Outside RSpec: `Approvals.configure { |c| c.approvals_path = "…" }`, default
`fixtures/approvals/` (`lib/approvals/configuration.rb:18-23`).

**(measured)** The name is derived from the example group and description,
joined as a directory path. `RSpec.describe "approvals DSL"` /
`it "verifies a value with a block"` produced
`spec/fixtures/approvals/approvals_dsl/verifies_a_value_with_a_block.approved.txt`.

### Argos (`@argos-ci/playwright` 7.4.6)

**(source)** A bare async function called inside an existing Playwright test —
not a matcher. The name is a **required** positional argument, documented as
"Name of the screenshot. Must be unique." (`dist/index.d.mts`, `argosScreenshot`).

```js
import { argosScreenshot } from "@argos-ci/playwright";

test("home", async ({ page }) => {
  await page.goto("/");
  await argosScreenshot(page, "home");
});
```

**(source)** Call-site options (`ArgosScreenshotOptions`, `dist/index.d.mts`):
`element` (Locator or selector), `viewports`, `ariaSnapshot`, `argosCSS`,
`disableHover` (default `true`), `threshold` (0–1, default `0.5`), `baseName`
(compare against a different screenshot's baseline; a list is tried in order),
`root` (default `"./screenshots"`), `tag`, `stabilize` (default `true`, or a
`StabilizationPluginOptions` object), `beforeScreenshot`, `afterScreenshot`.
Playwright's own `PageScreenshotOptions` / `LocatorScreenshotOptions` are
merged in, minus `encoding`, `type`, `omitBackground` and `path`.

**(source)** A second assertion, `argosAriaSnapshot(handler, name, options?)`,
captures an accessibility tree instead of pixels.

**(source)** Configuration is a Playwright reporter entry, plus environment:
`reporter: [["@argos-ci/playwright/reporter", { uploadToArgos: !!process.env.CI }]]`.

### BackstopJS 6.3.25 — no call-site DSL

**(measured)** There is no assertion. The unit of work is a **scenario object in
`backstop.json`**, and the tool is driven by `backstop reference` / `backstop
test` / `backstop approve`. Verbatim from `npx backstop init` on this machine:

```json
{
  "id": "backstop_default",
  "viewports": [
    { "label": "phone",  "width": 320,  "height": 480 },
    { "label": "tablet", "width": 1024, "height": 768 }
  ],
  "onBeforeScript": "puppet/onBefore.js",
  "onReadyScript": "puppet/onReady.js",
  "scenarios": [
    {
      "label": "BackstopJS Homepage",
      "cookiePath": "backstop_data/engine_scripts/cookies.json",
      "url": "https://garris.github.io/BackstopJS/",
      "referenceUrl": "",
      "readyEvent": "",
      "readySelector": "",
      "delay": 0,
      "hideSelectors": [],
      "removeSelectors": [],
      "hoverSelector": "",
      "clickSelector": "",
      "postInteractionWait": 0,
      "selectors": [],
      "selectorExpansion": true,
      "expect": 0,
      "misMatchThreshold" : 0.1,
      "requireSameDimensions": true
    }
  ],
  "paths": { … },
  "report": ["browser"],
  "engine": "puppeteer",
  "engineOptions": { "args": ["--no-sandbox"] },
  "asyncCaptureLimit": 5,
  "asyncCompareLimit": 50,
  "debug": false,
  "debugWindow": false
}
```

Scoping and tolerance are per-scenario fields, not per-call arguments:
`selectors` (`"document"` or CSS selectors — one bitmap per selector),
`hideSelectors` (`visibility: hidden`), `removeSelectors` (`display: none`),
`misMatchThreshold`, `requireSameDimensions`, `delay`, `readySelector`.
Stability hooks are **file paths to scripts** (`onReadyScript`), not closures.

**(measured)** Naming is fully derived, from config: the emitted bitmaps were
`demo_Home_page_0_document_0_phone.png` —
`{id}_{label}_{selectorIndex}_{selector}_{viewportIndex}_{viewportLabel}.png`.
Two viewports × two scenarios produced four bitmaps from two scenario objects.

### Chromatic — no call-site DSL

**(source)** No assertion exists. The inputs are **Storybook stories**; the CLI
(`npx chromatic --project-token=…`) builds the Storybook and uploads it.
Per-snapshot behaviour is set through Storybook `parameters`, attachable at
story, component (meta) and project level
([Parameters & Globals](https://www.chromatic.com/docs/params/)):

```js
export const Primary = {
  parameters: {
    chromatic: {
      delay: 300,
      diffThreshold: 0.063,
      diffIncludeAntiAliasing: false,
      pauseAnimationAtEnd: true,
      ignoreSelectors: [".timestamp"],
      viewports: [320, 1200],
      disableSnapshot: false,
      modes: { dark: { theme: "dark" } },
    },
  },
};
```

Documented `parameters.chromatic` keys: `delay`, `diffIncludeAntiAliasing`,
`diffThreshold`, `disableSnapshot`, `ignoreSelectors`, `pauseAnimationAtEnd`,
`forcedColors`, `prefersReducedMotion`, `media`, `cropToViewport`, `modes`,
`viewports`. `diffThreshold` default is stated as `.063`.

**(source)** `chromatic.modes` produces one snapshot per applied mode, "treated
separately, with independent baselines and distinct approvals"
([Story Modes](https://docs.chromatic.com/docs/modes/)) — the tool's mechanism
for several snapshots from one story.

### insta (Rust) 1.48.0

**(measured)** A family of macros, one per serialisation format. Name optional:

```rust
insta::assert_debug_snapshot!(user());                      // name from the test fn
insta::assert_yaml_snapshot!("explicit_name", user());      // explicit name first
insta::assert_snapshot!(format!("{}", 1));                  // Display
insta::assert_json_snapshot!(user(), { ".id" => "[id]" });  // redactions
insta::assert_snapshot!("hello", @"hello");                 // inline snapshot
```

**(source)** The full family, from `insta-1.48.0/src/macros.rs`:
`assert_snapshot!`, `assert_debug_snapshot!`, `assert_display_snapshot!`,
`assert_compact_debug_snapshot!`, `assert_yaml_snapshot!`,
`assert_json_snapshot!`, `assert_compact_json_snapshot!`,
`assert_ron_snapshot!`, `assert_toml_snapshot!`, `assert_csv_snapshot!`,
`assert_binary_snapshot!` — one per serialisation, rather than one macro with a
format option.

**(measured)** Call-site scoping is a **block macro** wrapping the assertions:

```rust
insta::with_settings!({ snapshot_suffix => "variant-a", omit_expression => true }, {
    insta::assert_debug_snapshot!(user());
});
```

`glob!("inputs/*.txt", |path| { … })` runs the enclosed assertions once per
matched file. `allow_duplicates!` changes the duplicate-name rule below.

**(source)** Configuration is a `Settings` object
(`Settings::new()` / `Settings::clone_current()` … `bind(|| …)`), plus
`insta.yaml` and environment variables (`INSTA_UPDATE`, `INSTA_FORCE_PASS`).

**(measured)** Naming — `{crate}__{module_path}__{name}.snap`:

| written | from |
|---|---|
| `dsl_demo__tests__debug_snapshot_derived_name.snap.new` | test fn name |
| `dsl_demo__tests__explicit_name.snap.new` | explicit first argument |
| `dsl_demo__tests__with_settings_block@variant-a.snap.new` | `snapshot_suffix` |

**(source)** Repeat snapshots in one test get `-2`, `-3`, … appended
(`runtime.rs:232-244`, insta 1.48.0). **(measured)** In a plain `cargo test`
the second assertion in a test is never reached, because the first panics:
`two_snapshots_in_one_test` produced exactly one `.snap.new`, holding the value
`1`, and the run printed `Stopped on the first failure. Run 'cargo insta test'
to run all snapshots.`

**(measured)** The `.snap.new` header records provenance:

```
---
source: src/lib.rs
assertion_line: 29
expression: "format!(\"{}\", 1)"
---
1
```

### Jest 30.4.2 — `toMatchSnapshot`

**(measured)** A matcher; the name is derived from the full test name.

```js
expect(user()).toMatchSnapshot();                          // "derived name 1"
expect(1).toMatchSnapshot('first');                        // hint
expect(user()).toMatchSnapshot({ id: expect.any(Number) }); // property matchers
expect(user()).toMatchSnapshot({ id: expect.any(Number) }, 'hint');
expect('hello').toMatchInlineSnapshot();                   // no file
```

**(measured)** The written `.snap` keys, from one run:

```
exports[`derived name 1`] = …
exports[`two in one test 1`] = `1`;
exports[`two in one test 2`] = `2`;
exports[`hint disambiguates: first 1`] = `1`;
exports[`hint disambiguates: second 1`] = `2`;
exports[`property matchers 1`] = `
{
  "createdAt": "2026-01-01",
  "id": Any<Number>,
  "name": "bob",
}
`;
```

Repeat snapshots in one test are disambiguated by an **ordinal appended to the
test name**; a hint is inserted before the ordinal as `: hint`. Property
matchers are stored in the file as `Any<Number>`, so the stored value is not a
literal.

**(measured)** `toMatchInlineSnapshot()` has no file: on the first run Jest
**rewrote the test source in place**, turning
`expect('hello').toMatchInlineSnapshot();` into
``expect('hello').toMatchInlineSnapshot(`"hello"`);``.

**(source)** Configuration is `jest.config.js` — `snapshotFormat`,
`snapshotResolver`, `snapshotSerializers`, `ci`, `updateSnapshot` — plus CLI
`-u` / `--ci`.

### jest-image-snapshot 6.5.2

**(measured)** A matcher, registered explicitly before use:

```js
const { toMatchImageSnapshot } = require('jest-image-snapshot');
expect.extend({ toMatchImageSnapshot });

expect(pngBuffer).toMatchImageSnapshot({
  customSnapshotIdentifier: 'box-explicit',
  failureThreshold: 0.01,
  failureThresholdType: 'percent',
  comparisonMethod: 'ssim',
  blur: 1,
  allowSizeMismatch: false,
  customDiffConfig: { threshold: 0.1 },
});
```

The subject is a **PNG buffer the caller supplies** — the matcher does no
capture, so scoping to an element is whatever produced the buffer.

**(measured)** With `customSnapshotIdentifier: 'box-explicit'` the baseline was
written to `__image_snapshots__/box-explicit.png` — a directory distinct from
Jest's `__snapshots__/`.

**(source)** Without it, `src/index.js:119-122` builds the name:

```js
const counter = snapshotState._counters.get(currentTestName);
const defaultIdentifier = kebabCase(`${path.basename(testPath)}-${currentTestName}-${counter}`);
let snapshotIdentifier = customSnapshotIdentifier || `${defaultIdentifier}-snap`;
```

The default therefore carries the **test file basename** as well as the test
name, and the counter is Jest's own per-test-name counter, incremented at
`:208`. `customSnapshotIdentifier` may also be a **function** receiving
`{ testPath, currentTestName, counter, defaultIdentifier }` (`:126-133`).

**(source)** Other options destructured in `src/index.js`: `customSnapshotsDir`,
`customDiffDir`, `customReceivedDir`, `storeReceivedOnFailure`,
`updatePassedSnapshot`, `diffDirection`, `onlyDiff`, `dumpDiffToConsole`,
`dumpInlineDiffToConsole`, `runtimeHooksPath`.

### Lost Pixel 3.22.0 — no call-site DSL

**(source)** No assertion. `lostpixel.config.ts` exports one object; the CLI
(`npx lost-pixel`, or `update` mode via arg, `-m`, or `LOST_PIXEL_MODE`)
consumes it. Shot sources are named blocks, one per integration
(`dist/config.d.ts`): `storybookShots`, `ladleShots`, `histoireShots`,
`pageShots`, `customShots`.

```ts
export const config = {
  pageShots: {
    baseUrl: "http://localhost:3000",
    pages: [{ path: "/", name: "home", threshold: 0.01, waitBeforeScreenshot: 500 }],
    mask: [{ selector: ".timestamp" }],
    breakpoints: [375, 1200],
  },
  threshold: 0,
};
```

Scoping and tolerance are per-page fields: `threshold`, `mask: [{ selector }]`,
`viewport`, `breakpoints`, `waitForSelector`, `waitBeforeScreenshot`.
`filterShot` and `shotNameGenerator` are **functions in the config file** —
the one place Lost Pixel takes user code.

### Percy (`@percy/playwright` 1.1.2)

**(source)** A bare function inside an existing test; the name is a **required**
positional argument (`types/index.d.ts`):

```js
const percySnapshot = require('@percy/playwright');

test('home', async ({ page }) => {
  await page.goto('/');
  await percySnapshot(page, 'Home page', {
    widths: [375, 1280],
    minHeight: 1024,
    percyCSS: '.timestamp { visibility: hidden; }',
    scope: '#main',
    enableJavaScript: false,
  });
});
```

**(source)** `SnapshotOptions` (`@percy/core/types/index.d.ts:51-70,128-131`):
`widths`, `scope`, `minHeight`, `percyCSS`, `enableJavaScript`,
`cliEnableJavascript`, `disableShadowDOM`, `domTransformation`, `enableLayout`,
`sync`, `responsiveSnapshotCapture`, `testCase`, `labels`,
`reshuffleInvalidTags`, `devicePixelRatio`, `scopeOptions`, `browsers`,
`pseudoClassEnabledElements`, plus `discovery` and `regions`. A `Region`
carries `algorithm`, `elementSelector`, `padding`, `configuration`
(`diffSensitivity`, `imageIgnoreThreshold`, `carouselsEnabled`,
`bannersEnabled`, `adsEnabled`) and `assertion` (`diffIgnoreThreshold`)
(`:92-110`).

**(source)** The CJS module exports the function as both the default and a
named export, alongside `percyScreenshot` and `createRegion`
(`index.js:584-588`).

**(source)** Configuration: `.percy.yml` (`snapshot:` and `discovery:` blocks,
mirroring `PercyConfigOptions`), the `PERCY_TOKEN` environment variable, and
the wrapping CLI `percy exec -- <test command>`. Tolerance appears only as
per-region fields sent with the snapshot (`diffSensitivity`,
`imageIgnoreThreshold`, `diffIgnoreThreshold`); no whole-snapshot threshold
appears in `CommonSnapshotOptions`, and comparison itself runs server-side —
so none of these was measured.

### Playwright 1.62.1 — `toHaveScreenshot`

**(measured)** A matcher. With no argument the name is derived from the test
title, slugified, with an ordinal:

```js
await expect(page).toHaveScreenshot();                 // whole-page-1.png
```

**(measured)** Two calls in one test take the ordinal `-1`, `-2`:

```js
await expect(page).toHaveScreenshot();  // two-shots-in-one-test-1.png
await expect(page).toHaveScreenshot();  // two-shots-in-one-test-2.png
```

**(measured)** An explicit name replaces the derived one entirely, and the
matcher also applies to a locator:

```js
await expect(page).toHaveScreenshot('header.png', {
  clip: { x: 0, y: 0, width: 300, height: 60 },
  mask: [page.locator('#clock')],
  maskColor: '#FF00FF',
  maxDiffPixelRatio: 0.02,
  animations: 'disabled',
  caret: 'hide',
  scale: 'css',
  timeout: 5000,
});

await expect(page.locator('#box')).toHaveScreenshot('box.png');   // element scoped
```

**(measured)** A second, lower-level matcher takes a buffer the caller
captured, which is how a non-page image enters the same pipeline:

```js
expect(await page.locator('#box').screenshot()).toMatchSnapshot('box-buffer.png');
```

**(measured)** Configuration — global defaults and the path scheme live in
`playwright.config.js`:

```js
module.exports = defineConfig({
  snapshotPathTemplate: '{testDir}/__screenshots__/{testFilePath}/{arg}{ext}',
  expect: { toHaveScreenshot: { maxDiffPixels: 10, threshold: 0.2 } },
  reporter: [['html', { open: 'never' }], ['list']],
});
```

**(source)** Global `expect.toHaveScreenshot` keys (`types/test.d.ts:198-247`):
`threshold`, `maxDiffPixels`, `maxDiffPixelRatio`, `animations`, `caret`,
`scale`, `stylePath`, `pathTemplate`, `timeout`.

**(measured)** `snapshotPathTemplate` is what removes the `-chromium-darwin`
suffix described in §2: the transcripts in that section use the default
template, the transcripts here use the custom one above.

### rspec-snapshot 2.2.0 (Ruby)

**(measured)** A matcher, and the name is **required**. Calling
`match_snapshot` with no argument raises
`ArgumentError: wrong number of arguments (given 0, expected 1..2)`.

```ruby
expect({ name: "bob" }).to match_snapshot("explicit_name")
expect(1).to match_snapshot("one")
expect(2).to match_snapshot("two")     # disambiguated by the caller, not the tool
```

**(source)** `match_snapshot(snapshot_name, config = {})`, aliased `snapshot`
(`lib/rspec/snapshot/matchers.rb:11-17`).

**(source)** Configuration
(`lib/rspec/snapshot/configuration.rb:8-15`):

```ruby
RSpec.configure do |c|
  c.snapshot_dir         = "spec/fixtures/snapshots"  # or :relative (default)
  c.snapshot_serializer  = nil
  c.snapshot_hash_syntax = :classic                   # or :modern
end
```

`:relative` puts snapshots in `__snapshots__/` beside the spec file
(`file_operator.rb:22-28`). Updating is the `UPDATE_SNAPSHOTS` environment
variable (`:64-70`); the same file carries the comment
`# TODO: Do not write to file if running in CI mode.` at `:49`, alongside the
open issue #32 recorded in §2.

### syrupy 6.0.0 (Python)

**(measured)** A pytest **fixture** compared with a plain `==`, not a matcher:

```python
def test_derived_name(snapshot):
    assert user() == snapshot

def test_named_snapshot(snapshot):
    assert user() == snapshot(name="explicit_name")

def test_exclude_fields(snapshot):
    assert user() == snapshot(exclude=props("created_at"))
```

**(measured)** Calling the fixture returns a configured assertion — that is the
call-site option mechanism. `exclude=props(…)` drops fields;
`snapshot.use_extension(JSONSnapshotExtension)` changes the serialiser and the
on-disk layout.

**(measured)** Naming and multiplicity, from one `--snapshot-update` run. The
default extension writes **one `.ambr` file per test module**, with named
sections:

```
# name: test_derived_name
# name: test_named_snapshot[explicit_name]
# name: test_two_in_one_test
# name: test_two_in_one_test.1
```

The derived name is the test function name; an explicit name appears as a
bracketed suffix, the same shape pytest uses for parametrised ids; repeat
snapshots in one test take `.1`, `.2`. The JSON extension instead wrote a
directory, `__snapshots__/test_dsl/test_json_extension.json`.

**(source)** Configuration is CLI flags on pytest, not a config block:
`--snapshot-update`, `--snapshot-update-new-only`, `--snapshot-warn-unused`,
`--snapshot-disable-unused`, `--snapshot-no-cleanup`, `--snapshot-details`,
`--snapshot-default-extension`, `--snapshot-no-colors`,
`--snapshot-patch-pycharm-diff`, `--snapshot-diff-mode={detailed,disabled}`.

### VCR 6.4.0 (Ruby)

**(measured)** A **block**, with the cassette name as a required argument:

```ruby
VCR.use_cassette("explicit_block", record: :none) do
  Net::HTTP.get(URI("http://example.com/"))
end
```

**(measured)** With `configure_rspec_metadata!`, `:vcr` metadata replaces the
block and derives the name from the example:

```ruby
it "names the cassette from the example", :vcr do
  Net::HTTP.get(URI("http://example.com/"))
end
```

wrote `spec/cassettes/VCR_DSL/names_the_cassette_from_the_example.yml` — group
description as directory, example description as file.

**(measured)** Configuration:

```ruby
VCR.configure do |c|
  c.cassette_library_dir = "spec/cassettes"
  c.hook_into :webmock
  c.default_cassette_options = { record: :once, match_requests_on: %i[method uri] }
  c.filter_sensitive_data("<TOKEN>") { "secret-abc" }
  c.ignore_hosts "localhost", "127.0.0.1"
  c.configure_rspec_metadata!
end
```

`VCR.insert_cassette` / `VCR.eject_cassette` are the non-block form.

### 3a. Naming, multiplicity and assertion shape

Rows alphabetical, as above. A `—` means the tool derives no name.

| Tool | Name derived from | Explicit name | Several per test |
|---|---|---|---|
| ApprovalTests (Ruby) | example group + description | `name:` / `namer:` option | not disambiguated automatically |
| Argos | — | required positional argument | distinct names, required unique |
| BackstopJS | scenario label + selector + viewport | scenario `label` field | one bitmap per selector × viewport |
| Chromatic | story id | — (story id is the name) | `chromatic.modes`, separate baselines |
| insta | test fn name | optional first argument | `-2`, `-3` suffix |
| Jest | full test name | optional hint argument | ordinal appended to the test name |
| jest-image-snapshot | test file basename + test name + counter | `customSnapshotIdentifier`, string or function | Jest's per-test-name counter |
| Lost Pixel | config `name` / story id | `name` field, `shotNameGenerator` | one shot per page × breakpoint |
| Percy | — | required positional argument | distinct names |
| Playwright | slugified test title + ordinal | optional first argument | `-1`, `-2` ordinal |
| rspec-snapshot | — | required first argument | distinct names, chosen by the caller |
| syrupy | test function name | `snapshot(name=…)`, stored bracketed | `.1`, `.2` suffix |
| VCR | example group + description, via `:vcr` | first argument of `use_cassette` | one cassette per block |

Assertion shape, grouped by form:

- **Matcher** — Jest, jest-image-snapshot, Playwright, rspec-snapshot.
- **Macro** — insta.
- **Bare function** — Argos, Percy.
- **Block** — ApprovalTests (Ruby), VCR, and insta's `with_settings!` / `glob!`.
- **Fixture compared with `==`** — syrupy.
- **No call-site DSL** — BackstopJS, Chromatic, Lost Pixel.

Two tools require an explicit name and will not derive one: Argos and Percy by
signature, rspec-snapshot by raising `ArgumentError` when the argument is
omitted (measured).

---

## 4. Reports, viewers and the review action

What is looked at after a failure, and what the reviewer does next. **Ordered
alphabetically by tool name**, with terminal-only tools grouped at the end.

Where a report was rendered on this machine, it was opened in headless Chromium
and its text and controls read from the live DOM; the transcripts below quote
that DOM. Hosted products were not exercised — those rows are `(source)`.

### Argos — hosted (source)

**(source)** Comparison modes on a build page
([Review a build](https://argos-ci.com/docs/learn/review-workflow/review-a-build.md)):
**Split view** (default, "baseline and changes side by side"); **Single view**
("one image at a time, switching between Baseline and Changes"); **Changes
overlay** ("changed pixels are highlighted with a red overlay. Toggle it on and
off, and customize its color and opacity"); **Fit or expand** (zoom and pan stay
in sync between panes); **ARIA view**, where an ARIA snapshot exists.

**(source)** Documented keyboard shortcuts:

| Action | Keys |
|---|---|
| Navigate snapshots | `↑` / `↓` |
| Show baseline / changes only | `←` / `→` |
| Toggle side-by-side | `S` |
| Toggle overlay | `D` |
| Highlight changes | `H` |
| Next / previous change | `J` / `K` |
| Mark accepted / rejected | `Y` / `N` |
| Open review popover | `↵` |

**(source)** At scale: screenshots are filtered by **Tags**, and a
review-progress chip shows how many changes have been reviewed.

**(source)** The review action is a click in a popover with three verdicts —
**Comment**, **Reject**, **Approve**. Each reviewer's latest decision counts:
"One rejection blocks", "one approval passes" with no active rejections.
Results surface in the Builds list, a PR comment, a commit/PR status check, and
the hosted build URL.

### BackstopJS — local HTML file (measured)

**(measured)** `backstop test` writes `backstop_data/html_report/`
(`index.html` + `config.js` holding the run data) and opens it. The landing
page is a **vertical list of cards, one per scenario × viewport**, each a
three-column grid labelled `REFERENCE` / `TEST` / `DIFF`, with the bitmap
filename above and a red rail down the left edge of a failing card.

**(measured)** Controls on the landing page: filter chips `all` / `0 passed` /
`4 failed`; a free-text box, placeholder `Filter tests with search...`;
per-card up/down chevrons; a settings control at the top right.

**(measured)** Clicking an image opens a full-screen modal whose mode buttons
are `REFERENCE`, `TEST`, `DIFF`, `SCRUBBER` — four modes, the last a
draggable wipe between reference and test.

**(measured)** The diff mask paints changed pixels **magenta** over the
reference.

**(measured)** Reviewing is a CLI command, not a click: `backstop approve`
prints the promotion list and copies the bitmaps.

```
Copying from backstop_data/bitmaps_test to backstop_data/bitmaps_reference.
The following files will be promoted to reference...
>  demo_Header_only_0_hdr_0_phone.png
>  demo_Header_only_0_hdr_1_desktop.png
>  demo_Home_page_0_document_0_phone.png
>  demo_Home_page_0_document_1_desktop.png
```

**(source)** `core/command/approve.js` shows the scope: it reads the **most
recent** test directory (`list[list.length - 1]`, `:19`), selects only files
matching `/^failed_diff_/` (`:5,:28`), and narrows them with `--filter`
compiled as a `RegExp` against the filename (`:29-34`), defaulting to `/\w+/`.
There is no per-image approve; the command promotes every failing bitmap the
filter admits.

**(measured)** `"report": ["browser"]` also accepts `"CI"` and `"json"`;
the run wrote `report.json` beside the bitmaps and `config.js` into the HTML
report directory.

### Chromatic — hosted (source)

**(source)** The Changeset tab shows "a side-by-side view of all visual
changes", and the highlighted diff — "in neon green" — can be toggled on and
off ([Review](https://www.chromatic.com/docs/review/)).

**(source)** The review action is a click: **Approve** in the Review screen tab
bar, with **Assign Reviewers** to nominate collaborators and **Resolve** to
close a threaded discussion attached to a snapshot. "All assigned reviewers must
approve." A `UI Review` status check reports the state on the pull request; an
Activity tab shows a timeline of builds, discussions and review status.

**(source)** A non-interactive path exists in the CLI, recorded in §2:
`--auto-accept-changes [branch]` and `--exit-zero-on-changes [branch]`.

### jest-image-snapshot — image files on disk (measured)

**(measured)** There is no viewer. A failure writes one composite PNG to
`__image_snapshots__/__diff_output__/<name>-diff.png` and names it in the
message:

```
Expected image to match or be a close match to snapshot but was
11.474392361111112% different from snapshot (105748 differing pixels).
See diff for details: …/__image_snapshots__/__diff_output__/page-diff.png
```

**(measured)** The composite is **three panes side by side**: for a 1280×720
baseline the diff file measured 3840×720, exactly 3 × 1280. Reviewing means
opening that file in an image viewer.

**(source)** `diffDirection: 'vertical'` stacks the three panes instead;
`dumpDiffToConsole` and the iTerm2/WezTerm inline-image path recorded in §2 put
the composite in the terminal itself.

**(measured)** The review action is a re-run with `-u`; the failure summary
prints the invocation, resolved from the caller's package manager — here
`Inspect your code changes or run 'npm run npx -- -u' to update them.`

### Percy — hosted (source)

**(source)** Per-snapshot the baseline is shown on the left and the new
screenshot on the right, with a generated visual diff overlaid on the new
screenshot; a side-by-side layout and an overlay layout are both offered
([Visual testing basics](https://www.browserstack.com/docs/percy/overview/visual-testing-basics)).
Documented shortcut keys include `d` to step through diffs and `t` to toggle
light/dark.

**(source)** The axes the build page exposes are legible in a public build URL,
which carries them as query parameters:

```
percy.io/Ember/web/guides-app/builds/45389416/changed/2401284869
  ?browser=firefox&browser_ids=69,70
  &group_snapshots_by=similar_diff
  &subcategories=unreviewed,changes_requested
  &viewLayout=side-by-side&viewMode=new
  &width=1280&widths=375,1280
```

— view layout, view mode, grouping by similar diff, subcategory filter, browser
and width filters, all as URL state.

**(source)** Approval is a click, at three scopes: a single snapshot, a group of
snapshots sharing a visual change, or the whole build. The CLI equivalents
recorded in §2 are `build:approve <build-id>`, `build:unapprove`,
`build:reject`.

### Playwright — local HTML folder (measured)

**(measured)** `npx playwright test` with the `html` reporter wrote
`playwright-report/` — `index.html` plus a `data/` directory of
content-hashed attachments, 592K for five failing tests. It renders both from
`npx playwright show-report` **and** directly from `file://`, images included
(both checked).

**(measured)** Landing page: a `Search tests` box, and filter chips carrying
counts — `All 5`, `Passed 0`, `Failed 5`, `Flaky 0`, `Skipped 0`. Tests are
grouped under their spec file, each row showing title, duration and
`file:line`.

**(source)** The search box is a small query language
(`packages/html-reporter/src/filter.ts:44-66`): `p:<project>`, `s:<status>`,
`@<label>`, `annot:<annotation>`, bare text, each prefixable with `!` to negate,
quoted strings supported. **(measured)** Typing `s:failed` produced the header
line `Filtered: 5 (1.4s)`.

**(measured)** A test detail page carries `« previous` and `next »` links that
step between tests, an `Errors` card with a `Copy prompt` button, a
`Test Steps` tree with its own `Filter steps` box, an
`Image mismatch: <name>` card, an `Attachments` list, and an
`Executed in Worker #N` line.

**(measured)** The image card offers **five** view modes, rendered as a row of
clickable labels: `Diff`, `Actual`, `Expected`, `Side by side`, `Slider`, with
the image dimensions beneath (`1280 x 720`) and three download links —
`…-diff.png`, `…-actual.png`, `…-expected.png`.

**(source)** `packages/web/src/shared/imageDiffView.tsx:102-106` at v1.62.1
renders those five. The `Diff` entry is conditional on a diff image existing
(`{diff.diff && …}`), so a comparison without one shows four. `:105-106` also
show that the right pane of `Side by side` toggles between `Actual` and `Diff`
on click, and that `Slider` is a two-image wipe.

**(measured)** A size mismatch still produced all five modes, and stated both
sizes in the message:
`Expected an image 200px by 100px, received 240px by 100px. 4000 pixels (ratio
0.17 of all image pixels) are different.`

**(measured)** The same image-mismatch view appears twice on the page: inline
inside the `Errors` card, and again in the `Image mismatch` card.

**(measured)** The review action is a re-run: `--update-snapshots`, modes as in
§2. Nothing in the report mutates a baseline. On disk the run also left
`test-results/<test-slug>/` per failing test, holding
`<name>-actual.png`, `-expected.png`, `-diff.png` and an `error-context.md`.

### 4a. Terminal-only tools

These have no viewer. What their text output does instead:

**RSpec 3.13** — **(measured)** `example_status_persistence_file_path` writes
the status table quoted in §2, which `--only-failures` and `--next-failure`
then consume: the "navigation" is a subsequent command, not a UI. RSpec also
ships an HTML formatter — `rspec --format html --out rspec-report.html`
produced a 7,488-byte self-contained file with `Passed` / `Failed` / `Pending`
toggles and a summary block.

**RuboCop 1.89.0** — **(measured)** `--help` lists 17 named output formatters:
`autogenconf`, `clang`, `emacs`, `files`, `fuubar`, `github`, `html`, `json`,
`junit`, `markdown`, `offenses`, `pacman`, `progress` (default), `quiet`,
`simple`, `tap`, `worst`, plus a custom class name. Two of those move the
result out of the terminal without a viewer: `--format html --out` wrote a
16,232-byte file, and `--format github` emits GitHub Actions workflow commands,
which the CI provider renders as inline annotations on the pull request diff:

```
::error file=bad.rb,line=1,col=1::Style/FrozenStringLiteralComment: Missing frozen string literal comment.
::error file=bad.rb,line=2,col=3::Lint/UselessAssignment: Useless assignment to variable - `x`.
::error file=bad.rb,line=4,col=1::Layout/EmptyLineBetweenDefs: Expected 1 empty line between method definitions; found 0.
::error file=bad.rb,line=4,col=1::Style/EmptyMethod: Put empty method definitions on a single line.
```

The review action is `--auto-gen-config` (record the offence as an exclusion)
or `-a` (change the source) — recorded in §2.

**SimpleCov 1.1.1** — **(measured)** Writes `coverage/index.html`, a local
file that renders from `file://`. The index is a sortable table — columns
`FILE NAME`, `LINE COVERAGE`, `COVERED`, `LINES`, `BRANCH COVERAGE`,
`COVERED`, `BRANCHES` — with per-column numeric filters offered as the
operators `<`, `≤`, `=`, `≥`, `>`, and a tab per configured group
(`All Files (71.42%)`, `Models (71.42%)`). Clicking a filename opens a
drill-down showing the source with a per-line hit count in the right gutter,
branch outcomes annotated inline (`then: 1`, `else: 0`), and a legend —
`Covered`, `Skipped`, `Missed line`, `Missed branch`. The header carries two
toggles, **`🎨 Colorblind`** and **`🌙 Dark`**. Footer:
`Generated 14 seconds ago by simplecov v1.1.1 using RSpec`.

There is no approve action; the gate is `minimum_coverage`, and the exit code
is the one recorded in §2.

**ApprovalTests / `approvals` (Ruby)** — **(measured)** On a mismatch the
failure prints the two paths and nothing else, because
`diff_on_approval_failure` defaults to `false`:

```
Approvals::ApprovalError:
  Approval Error: Received file "…/verifies_a_value_with_a_block.received.txt"
  does not match approved "…/verifies_a_value_with_a_block.approved.txt".
```

Setting `c.diff_on_approval_failure = true` routes the comparison through
`RSpec::Expectations.fail_with`, which prints RSpec's own diff
(`lib/approvals/extensions/rspec/dsl.rb:24-30`).

**(measured)** The review surface is a **dotfile plus an external diff tool**.
Each failure appends an `approved received` pair to `.approvals` in the working
directory:

```
spec/fixtures/approvals/approvals_dsl/verifies_a_value_with_a_block.approved.txt spec/fixtures/approvals/approvals_dsl/verifies_a_value_with_a_block.received.txt
```

**(source)** `approvals verify` walks that file, shells out to a diff tool
(`--diff`, default `diff -N`, e.g. `opendiff`, `vimdiff`), prompts
`Approve? [y/N]` per pair, and on yes runs `mv <received> <approved>`; rejected
pairs are written back to `.approvals` (`lib/approvals/cli.rb:6-33`). The review
action is literally a file move.

**rspec-snapshot 2.2.0** — **(measured)** The matcher sets `diffable? => true`,
so RSpec's own differ renders the change inline:

```
expected: {
  :name => "bob"
}
     got: {
  :name => "CHANGED"
}

Diff:
@@ -1,3 +1,3 @@
 {
-  :name => "bob"
+  :name => "CHANGED"
 }
```

The review action is a re-run with `UPDATE_SNAPSHOTS` set.

**insta 1.48.0** — **(measured)** The failure body is a boxed summary naming
the snapshot file, the source location and the originating expression, followed
by a line-numbered diff:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Snapshot Summary ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Snapshot file: src/snapshots/dsl_demo__tests__with_redactions.snap
Snapshot: with_redactions
Source: src/lib.rs:35
────────────────────────────────────────────────────────────────────────────────
Expression: user()
────────────────────────────────────────────────────────────────────────────────
+new results
────────────┬───────────────────────────────────────────────────────────────────
          1 │+{
          2 │+  "id": "[id]",
          3 │+  "name": "bob"
          4 │+}
────────────┴───────────────────────────────────────────────────────────────────
To update snapshots run `cargo insta review`
Stopped on the first failure. Run `cargo insta test` to run all snapshots.
```

The review action is the interactive `cargo insta review` TUI, or
`accept` / `reject` — recorded in §2.

**syrupy 6.0.0** — **(measured)** pytest prints a per-run
`snapshot report summary` block below the test results:

```
--------------------------- snapshot report summary ----------------------------
5 snapshots passed. 1 snapshot unused.

Unused test_exclude_fields (__snapshots__/test_dsl.ambr)
Re-run pytest with --snapshot-update to delete unused snapshots.
4 passed in 0.01s
```

(`--snapshot-details` adds the `Unused …` line.) The review action is a re-run
with `--snapshot-update`, which both writes new snapshots and deletes unused
ones unless `--snapshot-no-cleanup` is given.

**VCR 6.4.0** — **(measured)** The message quoted in §2 is the whole surface;
there is no artifact to open. The review action is editing the cassette YAML,
deleting it, or changing the record mode in source.

### 4b. Where the artifact lives, and how the review happens

| Tool | Artifact | Review action |
|---|---|---|
| ApprovalTests (Ruby) | `.received.*` files + a `.approvals` dotfile | external diff tool, then `mv` (`approvals verify`) |
| Argos | hosted build page | click: Approve / Reject / Comment |
| BackstopJS | local `html_report/` folder + `bitmaps_test/<timestamp>/` + `report.json` | CLI: `backstop approve` |
| Chromatic | hosted build page | click: Approve; or `--auto-accept-changes` |
| insta | `.snap.new` files | `cargo insta review` / `accept` / `reject` |
| Jest | `.snap` file, terminal diff | re-run with `-u` |
| jest-image-snapshot | one composite PNG per failure | re-run with `-u` |
| Lost Pixel | not observed — see §7 | re-run in `update` mode (`utils.ts:56-58`) |
| Percy | hosted build page | click, at snapshot / group / build scope; or `percy build:approve` |
| Playwright | local `playwright-report/` folder + `test-results/` | re-run with `--update-snapshots` |
| RSpec | terminal, or `--format html --out` | n/a |
| RuboCop | terminal, `--format html`, or `--format github` annotations | `--auto-gen-config` or `-a` |
| rspec-snapshot | terminal diff | re-run with `UPDATE_SNAPSHOTS` |
| SimpleCov | local `coverage/index.html` | n/a |
| syrupy | `.ambr` / per-test files, terminal summary | re-run with `--snapshot-update` |
| VCR | cassette YAML | edit or delete the cassette |

Grouped by mechanism, the review action is: a **click** for the three hosted
products (Argos, Chromatic, Percy); a **re-run of the test command with a flag**
for Jest, jest-image-snapshot, Lost Pixel, Playwright, rspec-snapshot and
syrupy; a **separate CLI command** for BackstopJS and insta; and a **file
operation** for ApprovalTests and VCR.

All three local HTML reports rendered here (BackstopJS, Playwright, SimpleCov)
opened from `file://` with images intact, without a server. Whether that is how
any project actually transports them was not investigated.

---

## 5. Cross-cutting mechanisms

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
- syrupy: on by default. **(measured)** Renaming one test so its snapshot went
  unreferenced produced `5 snapshots passed. 1 snapshot unused.` and **exit 1
  with zero failed tests**; `--snapshot-warn-unused` returned that run to exit
  0, and `--snapshot-update` deletes the unused entries unless
  `--snapshot-no-cleanup` is given. **(measured)** A filtered run
  (`pytest -k derived`) printed no unused report and exited 0, so the check does
  not fire on a partial suite — the failure mode jest-image-snapshot's README
  warns about for its own flag.
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

## 6. History of default changes

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

## 7. Not covered

- **Applitools** — CLI text and behaviour not obtainable without an account.
- **percy-capybara specifically** — the CLI it drives was exercised; nothing
  Capybara-specific was observed beyond the above.
- **Lost Pixel user-facing messages and report** — mode dispatch was read
  (`utils.ts:56-58`) and the config schema was read from `dist/config.d.ts` for
  §3, but the tool was never run: no failure output, no artifact and no viewer
  were observed. It therefore has a §3 entry and no §4 entry.
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
  rendering was checked against a deuteranopia or protanopia simulation. One
  correction to the earlier "none surveyed was observed documenting a
  colour-blind-safe palette": **SimpleCov 1.1.1 ships a `🎨 Colorblind` toggle**
  in its HTML report header (measured). That is a coverage report, not a diff
  artefact, and the palette it switches to was not evaluated — but the claim as
  written was too broad. Argos documents that the overlay colour and opacity are
  customisable (source); no surveyed tool was observed shipping a named
  colour-blind mode for an image diff.
- **Baseline storage growth over time** — not measured for any tool.
- **Tolerance/anti-aliasing for tools other than Playwright and
  jest-image-snapshot** — not gathered. §3 records the *named knobs* for
  BackstopJS (`misMatchThreshold`), Lost Pixel (`threshold`), Argos
  (`threshold`, default 0.5), Chromatic (`diffThreshold`, default `.063`) and
  Percy (`diffSensitivity`, `imageIgnoreThreshold`, `diffIgnoreThreshold`), but
  **no two of these were shown to mean the same thing**, and none was measured.
  §2b's finding about a shared pixelmatch parameter does not generalise to them.
- **Chromatic's UI Tests build page** — the review docs describe the Changeset
  side-by-side view and the neon-green diff toggle, but four fetches of
  `chromatic.com/docs/{review,snapshots,test,config-reference}` produced nothing
  on: how snapshots are grouped or filtered on a build, keyboard shortcuts, the
  verbatim labels of the accept/deny controls, or whether accept is per snapshot
  as well as per review. Recorded as unknown rather than guessed.
- **Percy and Chromatic keyboard navigation at scale** — Percy's `d` and `t`
  keys were found in vendor material; no complete shortcut table was located for
  either product, and neither was exercised. Argos was the only hosted product
  with a documented shortcut table.
- **BackstopJS's settings control and per-card chevrons** — the top-right
  control on the report was visible in the screenshot but could not be opened
  by the DOM selectors tried, so what it configures is unknown. The per-card
  up/down chevrons were likewise not exercised.
- **How any viewer behaves with 200 screenshots rather than 4** — not tested for
  any tool. The Playwright report was measured with 5 tests, BackstopJS with 4
  bitmaps, SimpleCov with 1 file. Filter and grouping *mechanisms* are recorded
  in §4; their behaviour under load, and any pagination or virtualisation, is
  not.
- **Trace viewer, video and `--last-failed`** — Playwright's trace artifact and
  its viewer sit alongside the HTML report and were not exercised; §4 covers the
  HTML report only.
- **Inline-snapshot rewriting beyond Jest** — Jest's in-place source rewrite was
  measured. insta's inline snapshots were written but the `cargo insta review`
  TUI, which performs the equivalent rewrite, was not driven (it is interactive);
  Vitest and AVA inline snapshots were not exercised at all.
- **ApprovalTests image reporters** — the gem ships `ImageMagickReporter` and
  `HtmlImageReporter` (files present in 0.1.7). Neither was configured or run,
  so what an image approval looks like in Ruby is unknown.
- **`percy-capybara`, and Ruby bindings for any hosted product** — §3 quotes the
  JavaScript SDKs, because those are what the published type declarations
  describe. No Ruby SDK's call-site signature was read.
- **BackstopJS under its default puppeteer engine** — see the caveat above; the
  engine would not launch on this machine.

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
Percy: [approval workflow](https://www.browserstack.com/docs/percy/build-results/approval) ·
[visual testing basics](https://www.browserstack.com/docs/percy/overview/visual-testing-basics) ·
[build review and approval](https://www.browserstack.com/percy/features/build-review-and-approval) ·
public build URL used for the view/filter parameters in §4:
[percy.io/Ember/web/guides-app/builds/45389416](https://percy.io/Ember/web/guides-app/builds/45389416/changed/2401284869?group_snapshots_by=similar_diff&subcategories=unreviewed%2Cchanges_requested&viewLayout=side-by-side&viewMode=new&widths=375%2C1280).
Chromatic: [branching and baselines](https://www.chromatic.com/docs/branching-and-baselines/) ·
[parameters & globals](https://www.chromatic.com/docs/params/) ·
[story modes](https://docs.chromatic.com/docs/modes/) ·
[review](https://www.chromatic.com/docs/review/).
Argos: [review a build](https://argos-ci.com/docs/learn/review-workflow/review-a-build.md).

Sources read from published packages rather than the web, at the versions in
the header — paths are relative to the installed package:

- Playwright: `packages/web/src/shared/imageDiffView.tsx:102-106` and
  `packages/html-reporter/src/filter.ts:44-66`, read at tag `v1.62.1` from
  `raw.githubusercontent.com/microsoft/playwright`; `playwright/types/test.d.ts:198-247`
  from the installed package.
- insta: `insta-1.48.0/src/runtime.rs:232-244` from the cargo registry checkout.
- Argos: `@argos-ci/playwright/dist/index.d.mts`.
- Percy: `@percy/playwright/types/index.d.ts`; `@percy/core/types/index.d.ts:51-70,92-110,128-131`.
- Lost Pixel: `lost-pixel/dist/config.d.ts`.
- BackstopJS: the `backstop.json` emitted by `backstop init` 6.3.25;
  `backstopjs/core/command/approve.js`.
- approvals: `lib/approvals/{configuration,approval,cli}.rb`,
  `lib/approvals/extensions/rspec.rb`, `lib/approvals/extensions/rspec/dsl.rb`,
  `lib/approvals/namers/directory_namer.rb`.
- rspec-snapshot: `lib/rspec/snapshot/{matchers,configuration,file_operator}.rb`
  and `lib/rspec/snapshot/matchers/match_snapshot.rb`.
- syrupy: `pytest --help` with the plugin installed.
