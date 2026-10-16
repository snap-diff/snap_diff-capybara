# frozen_string_literal: true

require "test_helper"
require "snap_diff/reporters/html"
require "unit/support_load_probe_test" # single source of truth for the -w probe

class HTMLReporterTest < ActiveSupport::TestCase
  include DSLStub

  setup do
    @output_dir = Pathname.new(Dir.mktmpdir)
    @output_path = @output_dir / "report.html"
  end

  teardown do
    @restore_root&.call
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

  # The reporter is usable on its own (record + finalize, no Reporting.count
  # behind it): its totals are what it recorded itself, never negative.
  test "#total and #passed come from what the reporter recorded, not from Reporting" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)

    reporter.record([build_failing_assertion("page_a"), build_passing_assertion("page_b")])

    assert_equal [2, 1, 1], [reporter.total, reporter.failed, reporter.passed]
    assert_equal 0, SnapDiff::Reporting.verified
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

  # A capture that vanished before the comparison has nothing to diff or
  # annotate. Without an explicit error the template infers "pass" from the
  # missing diff keys, so the entry says what went wrong instead.
  test "#record shows a vanished capture as an error, not a pass" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    compare = make_comparison(:a, :b, destination: "gone")
    FileUtils.rm compare.image_path
    compare.processed
    assertion = SnapDiff::ScreenshotAssertion.new("gone").tap { |a| a.compare = compare }

    reporter.record([assertion])

    entry = reporter.failures.sole
    assert_match(/missing/i, entry[:error])
    assert_nil entry[:diff]
    assert_nil entry[:new], "there is no capture to show"
    assert entry[:original], "the baseline is still there to show"
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

  # --- new screenshots (no committed baseline) ---------------------------
  #
  # Read from SnapDiff::Reporting.uncompared -- the entries behind the
  # summary line's "N new" -- so the report and the terminal agree.

  test "a run with only new screenshots writes a report listing them" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    path = capture_new_screenshot("signup")

    reporter.finalize

    assert_predicate @output_path, :exist?
    entry = report_data.sole
    assert_equal({"name" => "signup", "new_screenshot" => true,
                  "new" => path.relative_path_from(@output_dir).to_s,
                  "git_add" => "git add -- screenshots/signup.png"}, entry)
    assert_equal "[snap_diff] Report: #{@output_path}", reporter.summary
  end

  test "new screenshots are listed after the failures" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    capture_new_screenshot("signup")
    reporter.record([build_failing_assertion("index"), build_passing_assertion("ok")])

    reporter.finalize

    assert_equal [["index", nil], ["signup", true]], report_data.map { |e| [e["name"], e["new_screenshot"]] }
    html = @output_path.read
    assert_includes html, "1 failed"
    assert_includes html, "1 passed"
    assert_includes html, "2 total"
    assert_includes html, "1 new"
    assert_includes html, "<title>SnapDiff Report — 1 failures, 1 new</title>"
  end

  # Copy-pasted into a shell from the report, so it must survive any path.
  test "the git add command quotes the path for the shell" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    capture_new_screenshot("sign up")

    reporter.finalize

    assert_equal "git add -- screenshots/sign\\ up.png", report_data.sole["git_add"]
  end

  # save_path "." puts captures at the root, and a name may start with a
  # dash: without `--`, git would take the path for an option.
  test "the git add command can't mistake the path for an option" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    capture_new_screenshot("-signup", dir: ".")

    reporter.finalize

    assert_equal "git add -- -signup.png", report_data.sole["git_add"]
  end

  # The template reads locals from the binding, which Ruby can't see: a
  # local assigned only for it warns on every suite run with warnings on.
  test "no other reporter can change what the report lists" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    capture_new_screenshot("signup")
    assert_raises(FrozenError) { SnapDiff::Reporting.uncompared.first.status = :rerecorded }

    reporter.finalize

    assert_equal ["signup"], report_data.map { |e| e["name"] }
  end

  test "the reporter loads without warnings under -w" do
    noise = SupportLoadProbeTest.verbose_load("snap_diff/reporters/html").lines.grep(%r{lib/snap_diff/})

    assert_empty noise
  end

  test "a screenshot outside the project root is named by its absolute path" do
    outside = Pathname.new(Dir.mktmpdir) / "elsewhere.png"
    FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), outside)
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    SnapDiff::Reporting.record_missing_baseline("elsewhere", path: outside)

    SnapDiff.config.stub(:root, @output_dir) { reporter.finalize }

    assert_equal "git add -- #{Shellwords.escape(outside.to_s)}", report_data.sole["git_add"]
  ensure
    FileUtils.remove_entry(outside.dirname) if outside
  end

  # #260: never show a file or a command that live state doesn't back. The
  # file is gone by the time the report is written: still listed -- the
  # count must match the summary -- with nothing to show and nothing to run.
  test "a new screenshot with no capture on disk is listed without image or command" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    SnapDiff::Reporting.record_missing_baseline("deleted", path: @output_dir / "screenshots/deleted.png")

    SnapDiff.config.stub(:root, @output_dir) { reporter.finalize }

    assert_equal [{"name" => "deleted", "new_screenshot" => true}], report_data
  end

  test "the report shows how many were re-recorded, only when some were" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    capture_new_screenshot("signup")
    reporter.finalize
    refute_includes @output_path.read, "re-recorded"

    @output_path.delete
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    SnapDiff::Reporting.record_rerecorded_baseline("accepted", path: @output_dir / "accepted.png")
    reporter.finalize
    assert_includes @output_path.read, "1 re-recorded"
    assert_equal ["signup"], report_data.map { |e| e["name"] }, "counted, not listed"
  end

  # Re-recorded screenshots are counted, not listed: alone, there is nothing
  # to show, and the summary line already names them.
  test "a run with only re-recorded screenshots writes no report" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    SnapDiff::Reporting.record_rerecorded_baseline("accepted", path: @output_dir / "accepted.png")

    assert_nil reporter.finalize
    assert_not @output_path.exist?
  end

  test "a report with failures only lists exactly the failures" do
    reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    reporter.record([build_failing_assertion("index")])

    reporter.finalize

    assert_equal reporter.failures.map { |e| e.transform_keys(&:to_s) }, report_data
    html = @output_path.read
    assert_includes html, "<title>SnapDiff Report — 1 failures</title>"
    assert_includes html, "0 new"
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

  # A capture under a project rooted at @output_dir, tallied the way
  # ScreenshotMatcher tallies it. The root is pinned for the rest of the
  # test so display paths are predictable.
  def capture_new_screenshot(name, dir: "screenshots")
    path = @output_dir / dir / "#{name}.png"
    path.dirname.mkpath
    FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), path)
    SnapDiff::Reporting.record_missing_baseline(name, path: path)
    original_root = SnapDiff.config.root
    SnapDiff.config.root = @output_dir
    @restore_root = -> { SnapDiff.config.root = original_root }
    path
  end

  def report_data
    json = @output_path.read[/^\s*var DATA = (.*);$/, 1]
    JSON.parse(json.gsub("<\\/", "</"))
  end

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
