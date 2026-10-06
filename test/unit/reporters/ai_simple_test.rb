# frozen_string_literal: true

require "test_helper"
require "tmpdir"

require "snap_diff/reporters/ai_simple"
require "snap_diff/reporters/html"
require "snap_diff/screenshot_assertion"

class AISimpleReporterTest < Minitest::Test
  # Stub the exact surface the reporter touches; a real comparison would
  # need vips, fixtures and a checked-out baseline for no extra coverage.
  StubDifference = Struct.new(:different, keyword_init: true) do
    def different? = different
    def original_image_path = Pathname("/nonexistent/base.png")
    def new_image_path = Pathname("/nonexistent/current.png")
    def to_h = {area_size: 42, region: [0, 0, 10, 10]}
  end
  StubCompare = Struct.new(:difference)
  StubAssertion = Struct.new(:name, :compare)

  # Minimal ScreenshotAssertion surface for gate tests.
  GateCompare = Struct.new(:difference) do
    def different? = difference.different?
    def error_message = "diff details"
  end

  # Clear stored AI results before each reporter test.
  def setup
    SnapDiff::AI.clear_results!
  end

  # Clear the suppression gate installed by a reporter test.
  def teardown
    SnapDiff::Contributions.register_suppression(nil)
  end

  # Build a screenshot assertion with a controllable comparison and a fixed caller trace.
  def gate_assertion(name, different: true)
    SnapDiff::ScreenshotAssertion.new(name).tap do |a|
      a.compare = GateCompare.new(StubDifference.new(different: different))
      a.caller = ["test.rb:1"]
    end
  end

  def build_assertion(name, different: true)
    StubAssertion.new(name, StubCompare.new(StubDifference.new(different: different)))
  end

  def similarity_backend(value)
    ->(name:, base:, current:, meta:) { {similarity: value} }
  end

  def build_reporter(backend)
    SnapDiff::Reporters::AISimple.new(backend: backend)
  end

  def test_records_only_different_assertions
    build_reporter(similarity_backend(0.5)).record([
      build_assertion("changed"),
      build_assertion("same", different: false),
      StubAssertion.new("pending", StubCompare.new(nil))
    ])

    assert_equal ["changed"], SnapDiff::AI.results.map { |r| r[:name] }
    assert_equal "real_bug", SnapDiff::AI.results.first[:verdict]
  end

  def test_backend_verdict_wins_over_thresholds
    backend = ->(name:, base:, current:, meta:) { {similarity: 0.99, verdict: "real_bug", confidence: 0.91} }
    build_reporter(backend).record([build_assertion("checkout")])

    result = SnapDiff::AI["checkout"]
    assert_equal "real_bug", result[:verdict]
    assert_in_delta 0.91, result[:confidence]
  end

  def test_silent_when_nothing_analyzed
    reporter = build_reporter(similarity_backend(0.99))
    reporter.finalize

    assert_nil reporter.summary
  end

  def test_summary_breaks_down_verdicts
    reporter = build_reporter(similarity_backend(0.5))
    reporter.record([build_assertion("a"), build_assertion("b")])

    assert_equal "[snap_diff:ai] 2 diff(s) analyzed: 2 real_bug", reporter.summary
  end

  def test_dump_and_merge_state_round_trip_for_fork_parallel
    build_reporter(similarity_backend(0.99)).record([build_assertion("homepage")])
    fragment = JSON.parse(JSON.generate(SnapDiff::AI.dump_state))
    SnapDiff::AI.clear_results!

    build_reporter(similarity_backend(0.5)).merge_state!(fragment)

    assert_equal "flaky", SnapDiff::AI["homepage"][:verdict]
  end

  def test_backend_failure_skips_the_assertion_instead_of_raising
    reporter = build_reporter(->(name:, base:, current:, meta:) { raise "model exploded" })

    _out, err = capture_io { reporter.record([build_assertion("boom")]) }

    assert_includes err, "model exploded"
    assert_empty SnapDiff::AI.results
  end

  def test_rejects_a_backend_that_does_not_respond_to_call
    assert_raises(ArgumentError) { build_reporter(Object.new) }
  end

  def test_unknown_backend_symbol_names_registered_alternatives
    error = assert_raises(ArgumentError) { build_reporter(:does_not_exist) }

    assert_includes error.message, ":clip"
  end

  def test_registered_backend_resolves_by_name
    SnapDiff::AI.register(:test_stub) { similarity_backend(0.99) }
    build_reporter(:test_stub).record([build_assertion("homepage")])

    assert_equal "flaky", SnapDiff::AI["homepage"][:verdict]
  ensure
    SnapDiff::AI.instance_variable_get(:@backends).delete(:test_stub)
  end

  def test_factory_failure_degrades_to_disabled_but_config_errors_raise
    SnapDiff::AI.register(:exploding) { raise "cannot reach the model server" }

    reporter = nil
    _out, err = capture_io { reporter = build_reporter(:exploding) }

    assert_includes err, "triage disabled"
    reporter.record([build_assertion("homepage")])
    assert_empty SnapDiff::AI.results
  ensure
    SnapDiff::AI.instance_variable_get(:@backends).delete(:exploding)
  end

  def test_clip_backend_degrades_to_disabled_without_informers
    begin
      require "informers"
      skip "informers is installed in this environment"
    rescue LoadError
      # expected: exercising the absence path
    end

    reporter = nil
    _out, err = capture_io { reporter = build_reporter(:clip) }

    assert_includes err, "triage disabled"
    reporter.record([build_assertion("homepage")])
    assert_empty SnapDiff::AI.results
  end

  def test_custom_thresholds
    SnapDiff::Reporters::AISimple.new(
      backend: similarity_backend(0.95), flaky: 0.90, intentional: 0.80
    ).record([build_assertion("homepage")])

    assert_equal "flaky", SnapDiff::AI["homepage"][:verdict]
  end

  def test_gate_suppresses_verdicts_not_in_fail_on
    SnapDiff::Reporters::AISimple.new(backend: similarity_backend(0.99), fail_on: %w[real_bug])

    assert_nil gate_assertion("homepage").validate
    assert_equal "flaky", SnapDiff::AI["homepage"][:verdict]
  end

  def test_gate_still_fails_real_bugs_and_quotes_ai_in_the_message
    SnapDiff::Reporters::AISimple.new(backend: similarity_backend(0.50), fail_on: %w[real_bug])

    message = gate_assertion("checkout").validate

    assert_includes message, "Screenshot does not match for 'checkout'"
    assert_includes message, "AI triage: REAL_BUG (custom, similarity=0.5)"
  end

  # Verify that an unknown verdict preserves the screenshot failure and appears in its message.
  def test_gate_always_fails_unknown_verdicts
    SnapDiff::Reporters::AISimple.new(backend: similarity_backend(nil), fail_on: %w[real_bug])

    message = gate_assertion("checkout").validate

    assert_includes message, "AI triage: UNKNOWN"
  end

  # Verify that a backend exception logs a warning and leaves the screenshot mismatch standing.
  def test_gate_lets_the_failure_stand_when_analysis_fails
    # The backend raising must not turn validation itself into an error:
    # the screenshot mismatch is the failure the developer needs.
    exploding = ->(name:, base:, current:, meta:) { raise "model server unreachable" }
    SnapDiff::Reporters::AISimple.new(backend: exploding, fail_on: %w[real_bug])

    message = nil
    _out, err = capture_io { message = gate_assertion("checkout").validate }

    assert_includes message, "Screenshot does not match for 'checkout'"
    assert_includes err, "Backend failed"
  end

  # Verify that validation and reporting share a single backend analysis for the same diff.
  def test_gate_analysis_is_memoized_for_the_reporter_pass
    calls = 0
    counting_backend = ->(name:, base:, current:, meta:) {
      calls += 1
      {similarity: 0.99}
    }
    reporter = SnapDiff::Reporters::AISimple.new(backend: counting_backend, fail_on: %w[real_bug])

    assertion = gate_assertion("homepage")
    assertion.validate
    reporter.record([assertion])

    assert_equal 1, calls
  end

  def test_no_gate_means_pure_advisory
    SnapDiff::Reporters::AISimple.new(backend: similarity_backend(0.99))

    message = gate_assertion("homepage").validate

    assert_includes message, "Screenshot does not match"
    refute_includes message, "AI triage:"
  end

  def test_gate_reanalyzes_when_the_same_name_is_compared_again
    similarities = [0.99, 0.50]
    backend = ->(name:, base:, current:, meta:) { {similarity: similarities.shift} }
    SnapDiff::Reporters::AISimple.new(backend: backend, fail_on: %w[real_bug])

    # First comparison classifies flaky and is suppressed...
    assert_nil gate_assertion("homepage").validate

    # ...but a FRESH comparison under the same name must be re-analyzed:
    # a stale "flaky" may never suppress a new regression.
    message = gate_assertion("homepage").validate
    assert_includes message, "AI triage: REAL_BUG"
    assert_equal "real_bug", SnapDiff::AI["homepage"][:verdict]
  end

  def test_unrecognized_backend_verdict_becomes_unknown
    backend = ->(name:, base:, current:, meta:) { {verdict: "uncertain"} }
    build_reporter(backend).record([build_assertion("checkout")])

    assert_equal "unknown", SnapDiff::AI["checkout"][:verdict]
  end

  def test_gate_fails_on_unrecognized_verdicts
    backend = ->(name:, base:, current:, meta:) { {verdict: "uncertain"} }
    SnapDiff::Reporters::AISimple.new(backend: backend, fail_on: %w[real_bug])

    assert_includes gate_assertion("checkout").validate, "AI triage: UNKNOWN"
  end

  def test_memo_is_scoped_to_inputs_not_just_the_difference_object
    calls = 0
    backend = ->(name:, base:, current:, meta:) {
      calls += 1
      {similarity: 0.99}
    }
    SnapDiff::Reporters::AISimple.new(backend: backend, fail_on: %w[real_bug])

    # Two assertion names SHARING one difference object must both analyze.
    shared = StubDifference.new(different: true)
    %w[one two].each do |name|
      SnapDiff::ScreenshotAssertion.new(name).tap do |a|
        a.compare = GateCompare.new(shared)
        a.caller = []
      end.validate
    end

    assert_equal 2, calls
  end
end

class AIVerdictTest < Minitest::Test
  def test_bands
    assert_equal "flaky", SnapDiff::AI.verdict(0.985)
    assert_equal "intentional", SnapDiff::AI.verdict(0.90)
    assert_equal "real_bug", SnapDiff::AI.verdict(0.50)
    assert_equal "unknown", SnapDiff::AI.verdict(nil)
  end

  def test_non_finite_and_non_numeric_similarities_are_unknown
    assert_equal "unknown", SnapDiff::AI.verdict(Float::INFINITY)
    assert_equal "unknown", SnapDiff::AI.verdict(Float::NAN)
    assert_equal "unknown", SnapDiff::AI.verdict("high")
  end
end

# The mix: AISimple writes the shared store, HTML annotates from it.
class AIHtmlReporterMixTest < Minitest::Test
  HtmlDifference = Struct.new(:ratio, keyword_init: true) do
    def different? = true
    def region_area_size = 42
    def meta = {max_color_distance: 3.21}
  end
  class HtmlReporterStub
    def annotated_base_image_path = nil
    def annotated_image_path = nil
    def heatmap_diff_path = nil
  end
  HtmlCompare = Struct.new(:difference) do
    def base_image_path = Pathname("/nonexistent/base.png")
    def image_path = Pathname("/nonexistent/current.png")
    def reporter = HtmlReporterStub.new
  end
  HtmlAssertion = Struct.new(:name, :compare)

  # Clear AI results and save annotation providers before testing HTML rendering.
  def setup
    SnapDiff::AI.clear_results!
    @saved_providers = SnapDiff::Contributions.instance_variable_get(:@providers).dup
  end

  # Restore annotation providers so custom contributors do not leak into later tests.
  def teardown
    SnapDiff::Contributions.instance_variable_set(:@providers, @saved_providers)
  end

  # Build an HTML reporter that writes report.html into the supplied directory.
  def html_reporter(dir)
    SnapDiff::Reporters::HTML.new(output_path: File.join(dir, "report.html"))
  end

  def failed_assertion(name)
    HtmlAssertion.new(name, HtmlCompare.new(HtmlDifference.new(ratio: 0.02)))
  end

  # Verify that rendering attaches stored AI data and text only to the matching screenshot.
  def test_failures_carry_ai_annotation_after_render
    SnapDiff::AI.record_result(
      name: "checkout", verdict: "real_bug", backend: "clip",
      similarity: 0.7312, summary: "CTA clipped"
    )

    Dir.mktmpdir do |dir|
      reporter = html_reporter(dir)
      reporter.record([failed_assertion("checkout"), failed_assertion("plain")])
      reporter.finalize

      checkout, plain = reporter.failures
      annotation = checkout[:annotations].find { |a| a[:source] == "ai" }
      assert_equal "real_bug", annotation[:data][:verdict]
      assert_equal "CTA clipped", annotation[:data][:summary]
      assert_equal "REAL_BUG (clip, similarity=0.7312) -- CTA clipped", annotation[:text]
      refute plain.key?(:annotations)
    end
  end

  # Verify that rendering includes AI results recorded after HTML collected the failure.
  def test_ai_result_recorded_after_html_record_still_renders
    # HTML auto-registers before AISimple, so its record runs first; the
    # annotation must attach at render regardless of reporter order.
    Dir.mktmpdir do |dir|
      reporter = html_reporter(dir)
      reporter.record([failed_assertion("checkout")])
      SnapDiff::AI.record_result(name: "checkout", verdict: "flaky", backend: "clip", similarity: 0.9912)
      reporter.finalize

      assert_equal "flaky", reporter.failures.first[:annotations].first[:data][:verdict]
    end
  end

  # Verify that the generated report contains the AI strip and stored verdict.
  def test_rendered_report_includes_ai_bar_markup
    SnapDiff::AI.record_result(name: "checkout", verdict: "flaky", backend: "clip", similarity: 0.9912)

    Dir.mktmpdir do |dir|
      reporter = html_reporter(dir)
      reporter.record([failed_assertion("checkout")])
      reporter.finalize

      html = File.read(File.join(dir, "report.html"))
      assert_includes html, "ai-bar"
      assert_includes html, '"verdict":"flaky"'
    end
  end

  # Verify that an empty AI store adds no annotation keys to failures or serialized report data.
  def test_rendered_report_without_ai_stays_clean
    # AI not enabled (store empty): entries must not gain an :annotations
    # key, and the serialized DATA must contain no annotations at all.
    Dir.mktmpdir do |dir|
      reporter = html_reporter(dir)
      reporter.record([failed_assertion("checkout"), failed_assertion("plain")])
      reporter.finalize

      reporter.failures.each { |entry| refute entry.key?(:annotations) }
      html = File.read(File.join(dir, "report.html"))
      refute_includes html, '"annotations":'
    end
  end

  # Verify that a contribution without a verdict retains its source and text in the report.
  def test_text_only_contribution_renders_its_text
    # A contributor without a verdict payload (the documented
    # TicketLinker shape) must still show its text, not a bare label.
    linker = Object.new
    linker.define_singleton_method(:annotate) { |name| {source: "jira", text: "PROJ-123"} }
    SnapDiff::Contributions.instance_variable_get(:@providers) << linker

    Dir.mktmpdir do |dir|
      reporter = html_reporter(dir)
      reporter.record([failed_assertion("checkout")])
      reporter.finalize

      html = File.read(File.join(dir, "report.html"))
      assert_includes html, '"source":"jira"'
      assert_includes html, '"text":"PROJ-123"'
      # and the sidebar badge JS renders the text, not just the source
      assert_includes html, "note.text"
    end
  end
end
