# frozen_string_literal: true

require "test_helper"
require "snap_diff/reporters/html"

class HTMLReporterTest < ActiveSupport::TestCase
  include DSLStub

  setup do
    @output_dir = Pathname.new(Dir.mktmpdir)
    @output_path = @output_dir / "report.html"
  end

  teardown do
    FileUtils.remove_entry(@output_dir)
  end

  # Requiring this file is the only thing that puts a reporter in the
  # default list -- nothing else in the suite registers one. Guards the
  # auto-registration block at the bottom of reporters/html.rb, which
  # goes through SnapDiff::Reporting.register since ADR-008 step 6.
  test "requiring the reporter auto-registers exactly one HTML reporter" do
    registered = SnapDiff::Reporting.reporters.count { |reporter| reporter.is_a?(SnapDiff::Reporters::HTML) }

    assert_equal 1, registered
  end

  test "#record with no assertions writes nothing" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    reporter.record([])

    assert_not @output_path.exist?
  end

  test "#record with passing assertions writes nothing" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)

    reporter.record([build_passing_assertion("index")])
    reporter.finalize

    assert_not @output_path.exist?
  end

  test "#record and #finalize with failing assertion generates HTML file" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)

    reporter.record([build_failing_assertion("index")])
    reporter.finalize

    assert @output_path.exist?
    html = @output_path.read
    assert_includes html, "<!DOCTYPE html>"
    assert_includes html, "index"
  end

  test "#record and #finalize includes summary stats" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)

    reporter.record([
      build_failing_assertion("page_a"),
      build_passing_assertion("page_b"),
      build_failing_assertion("page_c")
    ])
    reporter.finalize

    html = @output_path.read
    assert_includes html, "2 failed"
    assert_includes html, "1 passed"
    assert_includes html, "3 total"
  end

  # An entry that fails to build must not vanish, nor sink the report: it is
  # warned about, kept as "could not render", and counted as failed.
  test "#record keeps an entry it could not build, says so, and renders the rest" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    broken = SnapDiff::ScreenshotAssertion.new("broken").tap { |a| a.compare = Object.new }

    _out, err = capture_io { reporter.record([broken, build_failing_assertion("valid")]) }

    assert_match(/\[snap_diff\] HTML report: could not render 'broken' \(NoMethodError: .*difference/, err)
    entry = reporter.failures.find { |e| e[:name] == "broken" }
    assert_match(/\ANoMethodError: .*difference/, entry[:error])
    assert_equal [2, 0], [reporter.failed, reporter.passed], "an entry the report can't vouch for is not a pass"

    reporter.finalize
    assert_includes @output_path.read, "valid"
  end

  test "#record counts an entry that fails before its comparison is read" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    broken = SnapDiff::ScreenshotAssertion.new("broken")
    broken.define_singleton_method(:compare) { raise "no compare" }

    capture_io { reporter.record([broken]) }

    assert_equal [1, 1, 0], [reporter.total, reporter.failed, reporter.passed]
  end

  # A dimension change fails with a frozen null ComparisonResult (no
  # region, failed_by: {different_dimensions: true}). Recording it used to
  # raise FrozenError, which #record swallowed, so the screenshot was
  # counted but silently left out of the report.
  test "#record reports a dimension change instead of skipping it" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)

    reporter.record([build_dimension_change_assertion("resized")])

    entry = reporter.failures.sole
    assert_equal "resized", entry[:name]
    assert_equal "80x80 => 80x60", entry[:dimensions_changed]
    assert entry[:original], "the baseline must be shown"
    assert entry[:new], "the new capture must be shown"

    reporter.finalize
    assert @output_path.exist?, "a run whose only failure is a dimension change still gets a report"
    assert_includes @output_path.read, "resized"
  end

  # Annotated and heatmap images are only drawn for same-size images. Any
  # on disk for this name are left over from an earlier, same-size failure
  # and describe a different comparison, so the entry must not link them.
  test "#record links no annotated images for a dimension change" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    assertion = build_dimension_change_assertion("stale")
    stale = assertion.compare.reporter
    [stale.annotated_image_path, stale.annotated_base_image_path, stale.heatmap_diff_path]
      .each { |path| FileUtils.cp(assertion.compare.image_path, path) }

    reporter.record([assertion])

    entry = reporter.failures.sole
    assert_nil entry[:diff]
    assert_nil entry[:base_diff]
    assert_nil entry[:heatmap]
  end

  test "HTML reporter defaults to screenshot root path" do
    reporter = SnapDiff::Reporters::HTML.new
    expected = SnapDiff.config.root / SnapDiff.config.save_path / "snap_diff_report.html"
    assert_equal expected, reporter.output_path
  end

  test "#record uses relative paths by default" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)

    reporter.record([build_failing_assertion("rel")])
    reporter.finalize

    html = @output_path.read
    assert_not_includes html, "data:image"
  end

  test "#record embeds base64 images when embed_images: true" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path, embed_images: true)

    reporter.record([build_failing_assertion("embed")])
    reporter.finalize

    html = @output_path.read
    assert_includes html, "data:image/png;base64,"
  end

  test "#record from multiple threads produces correct totals" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    threads = 10
    assertions_per_thread = 5

    workers = threads.times.map do
      Thread.new do
        batch = assertions_per_thread.times.map { |i| build_passing_assertion("t#{Thread.current.object_id}_#{i}") }
        reporter.record(batch)
      end
    end
    workers.each(&:join)

    assert_equal threads * assertions_per_thread, reporter.total
  end

  test "#record and #finalize synchronize internal state" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)

    fake_mutex = Class.new do
      attr_reader :synchronize_calls

      def initialize
        @synchronize_calls = 0
      end

      def synchronize
        @synchronize_calls += 1
        yield
      end
    end.new

    # Using private state and a fake mutex here is intentional.
    # This test guards a tricky synchronization detail; avoid refactors unless behavior changes.
    reporter.instance_variable_set(:@mutex, fake_mutex)

    reporter.record([build_passing_assertion("sync")])
    reporter.finalize

    assert_operator fake_mutex.synchronize_calls, :>=, 1
  end

  test "#finalize returns output_path when there are failures" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    reporter.record([build_failing_assertion("fail")])
    result = reporter.finalize

    assert_instance_of Pathname, result
  end

  test "#finalize returns nil when no failures" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    reporter.record([build_passing_assertion("pass")])
    result = reporter.finalize

    assert_nil result
  end

  # The COUNTS moved to SnapDiff::Reporting (issue #269) -- see
  # test/unit/reporting_counts_test.rb. What is left here is the one thing
  # only this reporter can say: where the file it wrote went.
  test "#summary names the report it wrote" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    reporter.record([build_failing_assertion("fail")])
    reporter.finalize

    assert_equal "[snap_diff] Report: #{@output_path}", reporter.summary
  end

  test "#summary is nil when no report was written" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    reporter.record([build_passing_assertion("ok")])
    reporter.finalize

    assert_nil reporter.summary, "nothing was written, so there is no path to name"
  end

  test "#finalize can retry after write_report failure" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    reporter.record([build_failing_assertion("retry")])

    # Make write_report fail on first attempt
    FileUtils.rm_rf(@output_dir)
    File.write(@output_dir.to_s, "not a directory")

    begin
      reporter.finalize
    rescue # rubocop:disable Lint/SuppressedException
    end

    # Restore writable directory and retry
    File.delete(@output_dir.to_s)
    FileUtils.mkdir_p(@output_dir)

    result = reporter.finalize
    assert_instance_of Pathname, result
    assert @output_path.exist?
  end

  private

  def build_passing_assertion(name)
    compare = make_comparison(:a, :a, destination: "pass_#{name}")
    compare.processed

    SnapDiff::ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
  end

  def build_failing_assertion(name)
    compare = make_comparison(:a, :b, destination: "fail_#{name}")
    compare.processed

    SnapDiff::ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
  end

  # a.png is 80x80, a_cropped.png is 80x60.
  def build_dimension_change_assertion(name)
    compare = make_comparison(:a, :a_cropped, destination: "resized_#{name}")
    compare.processed

    SnapDiff::ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
  end
end
