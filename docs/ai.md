# AI-assisted diff triage

> Optional and offline-first. Advisory by default — the pixel comparison
> stays the verdict and AI classifies failures so you know which reds to
> look at first. Opt into `fail_on:` to let the AI verdict gate failures.

`SnapDiff::Reporters::AISimple` analyzes every comparison that **already
failed** and labels it:

| Verdict | Meaning | Typical cause |
| --- | --- | --- |
| `flaky` | Pixels differ, semantics identical | Anti-aliasing, timestamps, avatars |
| `intentional` | Semantics shifted within a familiar shape | Redesign, copy change |
| `real_bug` | Semantics moved substantially | Clipped text, overlap, missing element |
| `unknown` | Backend could not score | Missing/unreadable image |

One line per diff in the test output, and — automatically, via the
shared store — a verdict badge plus one-line summary per failure in
`snap_diff_report.html`. No files, no duplicate storage.

## How reports get AI annotations

Core never names the AI module. It exposes one registry,
`SnapDiff::Contributions`, and loading `snap_diff/ai` self-registers
into it — the same shape as Minitest plugins appending to the
`CompositeReporter`, or SimpleCov formatters receiving a plain payload:

- `AISimple` writes each result into the shared `SnapDiff::AI` store
  (keyed by screenshot name).
- `SnapDiff::AI.annotate(name)` adapts a stored result to the generic
  `{source:, text:, data:}` contribution shape.
- The HTML reporter and the assertion failure message ask
  `Contributions.annotations_for(name)` and render whatever comes back —
  empty when AI was never loaded, so the no-AI report is byte-clean.

```ruby
require "snap_diff/reporters/html"       # already auto-registers
require "snap_diff/reporters/ai_simple"  # self-registers into Contributions
SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new)
```

Your own module can contribute the same way — no edits to core:

```ruby
module TicketLinker
  def self.annotate(name)
    ticket = JIRA_FOR[name]
    ticket && {source: "jira", text: ticket}
  end
end
SnapDiff::Contributions.register(TicketLinker)
```

The report then shows, per failure: an `AI: real bug` / `AI: flaky` badge
in the sidebar and top strip, plus `similarity · confidence · summary`
when the backend provides them. Under fork-parallel, results merge in the
parent before the report renders.

```
[snap_diff:ai] homepage: FLAKY (clip, similarity=0.9912)
  pixels differ but semantics match -- candidate for skip_area or a tolerance bump
[snap_diff:ai] checkout: REAL_BUG (clip, similarity=0.7312)
[snap_diff:ai] 2 diff(s) analyzed: 1 real_bug, 1 flaky
```

## Architecture

```
lib/snap_diff/contributions.rb       # core registry: annotations + the one failure gate
lib/snap_diff/ai.rb                  # backend registry, verdict thresholds, shared store; self-registers
lib/snap_diff/ai/backends/clip.rb    # built-in offline backend (informers)
lib/snap_diff/reporters/ai_simple.rb # record/finalize/summary; suppression via Contributions
lib/snap_diff/reporters/html.rb      # renders Contributions.annotations_for — no AI reference
lib/snap_diff/screenshot_assertion.rb# validate: Contributions gate + annotation lines
```

A backend is any object with `#call(name:, base:, current:, meta:) -> Hash`.
Extend without editing existing files:

```ruby
SnapDiff::AI.register(:jev) { JevBackend.new }   # optional requires go in the block
```

The returned hash may carry `:verdict` (used as-is) or `:similarity`
(classified by the shared thresholds); any other keys (`:confidence`,
`:summary`, `:auto_accept`) pass through to the report untouched.

## Setup

Default backend: CLIP via [`informers`](https://github.com/ankane/informers)
— ONNX Runtime, fully offline, ~90 MB quantized model, ~40 ms/image.

```ruby
# Gemfile
gem "informers"   # pulls onnxruntime itself

# test/test_helper.rb
require "snap_diff/reporters/ai_simple"
SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new)
```

Without `informers`, one warning at registration, then silence — never a
failed build.

**Prefetch the model.** The ~90 MB download happens on the first analyzed
diff, so a fully offline run needs a prefilled cache. Warm it at suite
setup (or as a cached CI step):

```ruby
SnapDiff::AI::Clip.new.prefetch!
```

Custom thresholds:

```ruby
SnapDiff::Reporters::AISimple.new(flaky: 0.99, intentional: 0.85)
```

## Gating failures on AI verdicts

Advisory mode never touches pass/fail. Add `fail_on:` and the verdict
decides: diffs classified as anything not listed are **suppressed** — the
test stays green, the result is still logged, stored, and shown in the
HTML report. `unknown` always fails: AI can downgrade a diff, never vouch
for one it could not classify.

```ruby
# Fail only on what AI calls a real bug; flaky/intentional stay green.
SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(fail_on: %w[real_bug]))
```

Failures that survive the gate quote the verdict inline, no clicks needed:

```
Screenshot does not match for 'checkout': the change spans ...
  AI triage: REAL_BUG (clip, similarity=0.7312) -- CTA clipped
```

Suppressed diffs log one line instead:

```
[snap_diff:ai] homepage: failure suppressed -- FLAKY (clip, similarity=0.9912)
```

## Backend recipes

### Typed decisions (TypeSafe Jev)

Jev answers typed questions (Choice / Score / Noul) over a state — text and
structured data, not images — so we send the diff *metrics*, not the pixels.
One call returns a verdict CI can branch on. Requires the community
[`typesafe-sdk`](https://rubygems.org/gems/typesafe-sdk) gem and
`TYPESAFE_API_KEY`:

```ruby
class JevBackend
  def name = "jev"

  def initialize
    require "typesafe/sdk"
    @client = Typesafe::SDK::Client.new(api_key: ENV.fetch("TYPESAFE_API_KEY"))
  end

  def call(name:, base:, current:, meta: {})
    resp = @client.system_one(
      state: {screenshot: name, changed_area_px: meta[:area_size], changed_region: meta[:region]},
      questions: {
        verdict: Typesafe::SDK::Choice.new(
          instructions: "Classify this visual diff",
          criteria: {
            flaky: "timestamp, anti-aliasing, or avatar noise",
            intentional: "deliberate redesign or copy change",
            real_bug: "clipped, overlapping, or missing UI"
          }
        ),
        auto_accept: Typesafe::SDK::Noul.new(instructions: "Safe to accept the new rendering as the baseline")
      }
    )
    answers = resp.answers
    {verdict: answers["verdict"].choice,
     confidence: answers["verdict"].confidence.round(2),
     auto_accept: answers["auto_accept"].noul.round(3)}
  end
end

SnapDiff::AI.register(:jev) { JevBackend.new }
SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(backend: :jev))
```

### Local VLM explanations (Qwen2.5-VL via Ollama)

```ruby
class QwenBackend
  def name = "qwen"

  def initialize
    require "ollama-ai"
    require "base64"
    @ollama = Ollama.new
  end

  def call(name:, base:, current:, meta: {})
    res = @ollama.chat(model: "qwen2.5vl:3b", messages: [{
      role: "user",
      content: "You are visual QA. Compare baseline vs current. " \
        'Return JSON {"summary": one sentence, "verdict": "real_bug|intentional|flaky"}.',
      images: [base, current].map { |p| Base64.strict_encode64(File.binread(p)) }
    }])
    content = res.dig("message", "content").to_s
    JSON.parse(content, symbolize_names: true).slice(:verdict, :summary)
  rescue JSON::ParserError
    {summary: content}
  end
end
```

### Hybrid: CLIP first, Qwen only where it pays

```ruby
class ClipThenQwen
  def name = "clip+qwen"

  def initialize
    @clip = SnapDiff::AI::Clip.new
    @qwen = QwenBackend.new
  end

  def call(name:, base:, current:, meta: {})
    result = @clip.call(name: name, base: base, current: current, meta: meta)
    sim = result[:similarity]
    return result if sim.nil? || sim >= 0.985 || sim < 0.90

    @qwen.call(name: name, base: base, current: current, meta: meta).merge(result)
  end
end
```

## CI gating

Use the built-in gate — no JSON parsing, no extra script:

```ruby
SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(fail_on: %w[real_bug]))
```

The suite then fails only on verdicts you list; see
[Gating failures on AI verdicts](#gating-failures-on-ai-verdicts).

## Guarantees

- **Advisory by default**: pass/fail changes only with an explicit `fail_on:` opt-in.
- **Thread-safe**: results behind one mutex; CLIP inference serialized.
- **Fork-parallel**: results are plain JSON-able hashes; workers merge via `dump_state`/`merge_state!`.
- **No hard deps**: `informers`, `typesafe`, `ollama-ai` all optional; gemspec unchanged.
