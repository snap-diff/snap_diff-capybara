# frozen_string_literal: true

require "test_helper"
require "tmpdir"

require "snap_diff/reporters/ai_simple"
require "snap_diff/reporters/html"

class AiSimpleReporterTest < Minitest::Test
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

  def setup
    SnapDiff::Ai.clear_results!
  end

  def build_assertion(name, different: true)
    StubAssertion.new(name, StubCompare.new(StubDifference.new(different: different)))
  end

  def similarity_backend(value)
    ->(name:, base:, current:, meta:) { {similarity: value} }
  end

  def build_reporter(backend, dir = Dir.mktmpdir)
    SnapDiff::Reporters::AiSimple.new(backend: backend, output_path: File.join(dir, "ai_report.json"))
  end

  def test_records_only_different_assertions
    build_reporter(similarity_backend(0.5)).record([
      build_assertion("changed"),
      build_assertion("same", different: false),
      StubAssertion.new("pending", StubCompare.new(nil))
    ])

    assert_equal ["changed"], SnapDiff::Ai.results.map { |r| r[:name] }
    assert_equal "real_bug", SnapDiff::Ai.results.first[:verdict]
  end

  def test_backend_verdict_wins_over_thresholds
    backend = ->(name:, base:, current:, meta:) { {similarity: 0.99, verdict: "real_bug", confidence: 0.91} }
    build_reporter(backend).record([build_assertion("checkout")])

    result = SnapDiff::Ai["checkout"]
    assert_equal "real_bug", result[:verdict]
    assert_in_delta 0.91, result[:confidence]
  end

  def test_finalize_writes_json_report
    Dir.mktmpdir do |dir|
      path = File.join(dir, "nested", "ai_report.json")
      SnapDiff::Reporters::AiSimple.new(backend: similarity_backend(0.99), output_path: path)
        .record([build_assertion("homepage")])
      SnapDiff::Reporters::AiSimple.new(backend: similarity_backend(0.99), output_path: path).finalize

      report = JSON.parse(File.read(path), symbolize_names: true)
      assert_equal [{name: "homepage", backend: "custom", similarity: 0.99, verdict: "flaky"}], report
    end
  end

  def test_silent_when_nothing_analyzed
    reporter = build_reporter(similarity_backend(0.99))
    reporter.finalize

    assert_nil reporter.summary
  end

  def test_summary_breaks_down_verdicts
    reporter = build_reporter(similarity_backend(0.5))
    reporter.record([build_assertion("a"), build_assertion("b")])

    assert_equal "[snap_diff:ai] 2 diff(s) analyzed: 2 real_bug (ai_report.json)", reporter.summary
  end

  def test_dump_and_merge_state_round_trip_for_fork_parallel
    build_reporter(similarity_backend(0.99)).record([build_assertion("homepage")])
    fragment = JSON.parse(JSON.generate(SnapDiff::Ai.dump_state))
    SnapDiff::Ai.clear_results!

    build_reporter(similarity_backend(0.5)).merge_state!(fragment)

    assert_equal "flaky", SnapDiff::Ai["homepage"][:verdict]
  end

  def test_backend_failure_skips_the_assertion_instead_of_raising
    reporter = build_reporter(->(name:, base:, current:, meta:) { raise "model exploded" })

    _out, err = capture_io { reporter.record([build_assertion("boom")]) }

    assert_includes err, "model exploded"
    assert_empty SnapDiff::Ai.results
  end

  def test_rejects_a_backend_that_does_not_respond_to_call
    assert_raises(ArgumentError) { build_reporter(Object.new) }
  end

  def test_unknown_backend_symbol_names_registered_alternatives
    error = assert_raises(ArgumentError) { build_reporter(:does_not_exist) }

    assert_includes error.message, ":clip"
  end

  def test_registered_backend_resolves_by_name
    SnapDiff::Ai.register(:test_stub) { similarity_backend(0.99) }
    build_reporter(:test_stub).record([build_assertion("homepage")])

    assert_equal "flaky", SnapDiff::Ai["homepage"][:verdict]
  ensure
    SnapDiff::Ai.instance_variable_get(:@backends).delete(:test_stub)
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
    assert_empty SnapDiff::Ai.results
  end

  def test_custom_thresholds
    SnapDiff::Reporters::AiSimple.new(
      backend: similarity_backend(0.95), flaky: 0.90, intentional: 0.80,
      output_path: File.join(Dir.mktmpdir, "ai_report.json")
    ).record([build_assertion("homepage")])

    assert_equal "flaky", SnapDiff::Ai["homepage"][:verdict]
  end
end

class AiVerdictTest < Minitest::Test
  def test_bands
    assert_equal "flaky", SnapDiff::Ai.verdict(0.985)
    assert_equal "intentional", SnapDiff::Ai.verdict(0.90)
    assert_equal "real_bug", SnapDiff::Ai.verdict(0.50)
    assert_equal "unknown", SnapDiff::Ai.verdict(nil)
  end
end

# The mix: AiSimple writes the shared store, HTML annotates from it.
class AiHtmlReporterMixTest < Minitest::Test
  HtmlDifference = Struct.new(:ratio, keyword_init: true) do
    def different? = true
    def region_area_size = 42
    def meta = {max_color_distance: 3.21}
  end
  HtmlReporterStub = Struct.new do
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

  def setup
    SnapDiff::Ai.clear_results!
  end

  def html_reporter(dir)
    SnapDiff::Reporters::HTML.new(output_path: File.join(dir, "report.html"))
  end

  def failed_assertion(name)
    HtmlAssertion.new(name, HtmlCompare.new(HtmlDifference.new(ratio: 0.02)))
  end

  def test_failures_carry_ai_annotation_when_present
    SnapDiff::Ai.record_result(
      name: "checkout", verdict: "real_bug", backend: "clip",
      similarity: 0.7312, summary: "CTA clipped"
    )

    Dir.mktmpdir do |dir|
      reporter = html_reporter(dir)
      reporter.record([failed_assertion("checkout"), failed_assertion("plain")])

      checkout, plain = reporter.failures
      assert_equal "real_bug", checkout[:ai][:verdict]
      assert_equal "CTA clipped", checkout[:ai][:summary]
      refute plain.key?(:ai)
    end
  end

  def test_rendered_report_includes_ai_bar_markup
    SnapDiff::Ai.record_result(name: "checkout", verdict: "flaky", backend: "clip", similarity: 0.9912)

    Dir.mktmpdir do |dir|
      reporter = html_reporter(dir)
      reporter.record([failed_assertion("checkout")])
      reporter.finalize

      html = File.read(File.join(dir, "report.html"))
      assert_includes html, "ai-bar"
      assert_includes html, '"verdict":"flaky"'
    end
  end
end
