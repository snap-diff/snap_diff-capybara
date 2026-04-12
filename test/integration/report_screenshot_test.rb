# frozen_string_literal: true

require "system_test_case"

class ReportScreenshotTest < SystemTestCase
  PERCEPTUAL_THRESHOLD = 2.0

  setup do
    screenshot_section "html_report"

    @report_dir = Pathname.new("test/fixtures/app/report")
    @report_path = @report_dir / "index.html"
    skip "Run with RECORD_SCREENSHOTS=1 to update report fixtures" unless ENV["RECORD_SCREENSHOTS"]
    generate_sample_report
    visit "/report/index.html"
  end

  teardown do
    FileUtils.rm_rf(@report_dir)
  end

  def test_report_both_view
    screenshot "report_both", perceptual_threshold: PERCEPTUAL_THRESHOLD
  end

  def test_report_base_view
    find("[data-view='base']").click
    screenshot "report_base", perceptual_threshold: PERCEPTUAL_THRESHOLD
  end

  def test_report_new_view
    find("[data-view='new']").click
    screenshot "report_new", perceptual_threshold: PERCEPTUAL_THRESHOLD
  end

  def test_report_heatmap_view
    find("[data-view='heatmap']").click
    screenshot "report_heatmap", perceptual_threshold: PERCEPTUAL_THRESHOLD
  end

  def test_report_annotated_both
    find("#annotate-toggle").click
    screenshot "report_annotated_both", perceptual_threshold: PERCEPTUAL_THRESHOLD
  end

  private

  def generate_sample_report
    img_dir = @report_dir / "images"
    img_dir.mkpath

    # Copy fixtures into served directory so browser can load them
    fixtures = Pathname.new("test/fixtures/images")
    %w[a.png b.png c.png].each { |f| FileUtils.cp(fixtures / f, img_dir / f) }

    # Run real comparisons inside the served directory
    assertions = [
      build_assertion("islands-map", img_dir / "a.png", img_dir / "b.png"),
      build_assertion("islands-variant", img_dir / "a.png", img_dir / "c.png")
    ]

    reporter = CapybaraScreenshotDiff::Reporters::HTML.new(output_path: @report_path)
    reporter.record(assertions)
    reporter.finalize
  end

  def build_assertion(name, base_path, new_path)
    # Copy to unique files so shared base images don't overwrite each other's annotations
    unique_base = @report_dir / "images" / "#{name}_base.png"
    unique_new = @report_dir / "images" / "#{name}_new.png"
    FileUtils.cp(base_path, unique_base)
    FileUtils.cp(new_path, unique_new)

    compare = Capybara::Screenshot::Diff::ImageCompare.new(unique_new, unique_base, driver: :vips)
    compare.processed
    CapybaraScreenshotDiff::ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
  end
end
