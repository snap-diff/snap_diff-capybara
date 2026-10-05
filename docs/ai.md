# AI-assisted diff triage

> Optional, offline-first, advisory only. The pixel comparison stays the
> verdict; AI classifies failures so you know which reds to look at first.

`SnapDiff::Reporters::AiSimple` analyzes every comparison that **already
failed** and labels it:

| Verdict | Meaning | Typical cause |
| --- | --- | --- |
| `flaky` | Pixels differ, semantics identical | Anti-aliasing, timestamps, avatars |
| `intentional` | Semantics shifted within a familiar shape | Redesign, copy change |
| `real_bug` | Semantics moved substantially | Clipped text, overlap, missing element |
| `unknown` | Backend could not score | Missing/unreadable image |

One line per diff in the test output, `ai_report.json` at end of run,
and — automatically — a verdict badge plus one-line summary per failure
in `snap_diff_report.html`.

## How the HTML report gets AI annotations

Both reporters read the same shared store: `AiSimple` writes each result
into `SnapDiff::Ai` (keyed by screenshot name), and the HTML reporter
attaches `SnapDiff::Ai[name]` to the failure entry — behind a `defined?`
guard, so `html.rb` never requires the AI module and nothing changes
when AI triage isn't loaded. No wiring between the two reporters:

```ruby
require "snap_diff/reporters/html"       # already auto-registers
require "snap_diff/reporters/ai_simple"
SnapDiff::Reporting.register(SnapDiff::Reporters::AiSimple.new)
```

The report then shows, per failure: an `AI: real bug` / `AI: flaky` badge
in the sidebar and top strip, plus `similarity · confidence · summary`
when the backend provides them. Under fork-parallel, results merge in the
parent before the report renders.

```
[snap_diff:ai:clip] homepage: FLAKY similarity=0.9912
  pixels differ but semantics match -- candidate for skip_area or a tolerance bump
[snap_diff:ai:clip] checkout: REAL_BUG similarity=0.7312
[snap_diff:ai] 2 diff(s) analyzed: 1 real_bug, 1 flaky (ai_report.json)
```

## Architecture

```
lib/snap_diff/ai.rb                  # backend registry, verdict thresholds, shared result store
lib/snap_diff/ai/backends/clip.rb    # built-in offline backend (informers)
lib/snap_diff/reporters/ai_simple.rb # record/finalize/summary; writes the store
lib/snap_diff/reporters/html.rb      # annotates failures from the store (defined? guard)
```

A backend is any object with `#call(name:, base:, current:, meta:) -> Hash`.
Extend without editing existing files:

```ruby
SnapDiff::Ai.register(:jev) { JevBackend.new }   # optional requires go in the block
```

The returned hash may carry `:verdict` (used as-is) or `:similarity`
(classified by the shared thresholds); any other keys (`:confidence`,
`:summary`, `:auto_accept`) pass through to the report untouched.

## Setup

Default backend: CLIP via [`informers`](https://github.com/ankane/informers)
— ONNX Runtime, fully offline, ~90 MB quantized model, ~40 ms/image.

```ruby
# Gemfile
gem "informers"   # plus onnxruntime

# test/test_helper.rb
require "snap_diff/reporters/ai_simple"
SnapDiff::Reporting.register(SnapDiff::Reporters::AiSimple.new)
```

Without `informers`, one warning at registration, then silence — never a
failed build.

**Prefetch the model.** The ~90 MB download happens on the first analyzed
diff, so a fully offline run needs a prefilled cache. Warm it at suite
setup (or as a cached CI step):

```ruby
SnapDiff::Ai::Clip.new.prefetch!
```

Custom thresholds:

```ruby
SnapDiff::Reporters::AiSimple.new(flaky: 0.99, intentional: 0.85)
```

## Backend recipes

### Typed decisions (TypeSafe Jev)

```ruby
class JevBackend
  def name = "jev"

  def initialize
    require "typesafe"
    @client = Typesafe::Client.new(api_key: ENV.fetch("TYPESAFE_API_KEY"))
  end

  def call(name:, base:, current:, meta: {})
    resp = @client.evaluate(
      state: {screenshot: name, area: meta[:area_size], region: meta[:region]},
      questions: {
        verdict: Typesafe::Choice.new("Classify visual diff", criteria: {
          flaky: "timestamp/anti-aliasing/avatar noise",
          intentional: "deliberate redesign or copy change",
          real_bug: "clipped, overlapping, or missing UI"
        }),
        auto_accept: Typesafe::Noul.new("Safe to accept?", criteria: {
          true => "flaky or intentional", false => "real bug"
        })
      }
    )
    {verdict: resp[:verdict].choice,
     confidence: resp[:verdict].confidence.round(2),
     auto_accept: resp[:auto_accept].noul.round(3)}
  end
end

SnapDiff::Ai.register(:jev) { JevBackend.new }
SnapDiff::Reporting.register(SnapDiff::Reporters::AiSimple.new(backend: :jev))
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
    JSON.parse(res, symbolize_names: true).slice(:verdict, :summary)
  rescue JSON::ParserError
    {summary: res}
  end
end
```

### Hybrid: CLIP first, Qwen only where it pays

```ruby
class ClipThenQwen
  def name = "clip+qwen"

  def initialize
    @clip = SnapDiff::Ai::Clip.new
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

## CI gating (auto-accept stays in userland)

```ruby
report = JSON.parse(File.read("doc/screenshots/ai_report.json"), symbolize_names: true)
real = report.select { |r| r[:verdict] == "real_bug" }
exit(real.empty? ? 0 : 1)
```

## Guarantees

- **Advisory**: never changes pass/fail; auto-accept is your CI script, not core.
- **Thread-safe**: results behind one mutex; CLIP inference serialized.
- **Fork-parallel**: results are plain JSON-able hashes; workers merge via `dump_state`/`merge_state!`.
- **No hard deps**: `informers`, `typesafe`, `ollama-ai` all optional; gemspec unchanged.
