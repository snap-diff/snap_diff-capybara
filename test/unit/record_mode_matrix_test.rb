# frozen_string_literal: true

require "test_helper"
require "snap_diff"
require "snap_diff/reporters/html"

# THE ACCEPTANCE MATRIX: what each record mode does with each kind of
# capture, end to end below the browser -- the status the capture ends in,
# what Reporting tallies, what is left on disk, whether the HTML report
# lists it, and whether the run fails.
#
# `:all` is `:once` that accepts instead of fails: the baseline is fetched
# and compared in every mode, and the comparison only labels the capture.
# The two differ in exactly one cell group: a capture that differs.
class RecordModeMatrixTest < ActiveSupport::TestCase
  include DSLStub

  FAILS = {status: :changed, verified: 1, changed: 1, rerecorded: 0, new: 0, entry: "changed", raises: true}.freeze
  ACCEPTED = {status: :rerecorded, verified: 1, changed: 1, rerecorded: 1, new: 0, entry: "rerecorded", raises: false}.freeze
  PASSES = {status: :passed, verified: 1, changed: 0, rerecorded: 0, new: 0, entry: nil, raises: false}.freeze

  # cell => [setup, {mode => expected}]. A setup is [baseline fixture, capture fixture,
  # matcher options]; nil baseline means none was committed.
  CELLS = {
    "new" => [[nil, :a, {}], {
      none: {status: :new, verified: 0, changed: 0, rerecorded: 0, new: 1, entry: "new", raises: true},
      once: {status: :new, verified: 0, changed: 0, rerecorded: 0, new: 1, entry: "new", raises: false},
      all: {status: :new, verified: 0, changed: 0, rerecorded: 0, new: 1, entry: "new", raises: false}
    }],
    "same" => [[:a, :a, {}], {none: PASSES, once: PASSES, all: PASSES}],
    "within tolerance" => [[:a, :b, {tolerance: 0.02}], {none: PASSES, once: PASSES, all: PASSES}],
    "differs" => [[:a, :c, {}], {none: FAILS, once: FAILS, all: ACCEPTED}],
    "dimensions changed" => [[:a, :a_cropped, {}], {none: FAILS, once: FAILS, all: ACCEPTED}]
  }.freeze

  def before_setup
    @original_root = SnapDiff.config.root
    @new_root = Dir.mktmpdir
    SnapDiff.config.root = Pathname.new(@new_root)
    @original_ci = ENV.delete("CI")
    super
  end

  def after_teardown
    super
    ENV["CI"] = @original_ci
    SnapDiff.config.root = @original_root
    FileUtils.remove_entry(@new_root) if @new_root
    SnapDiff::Reporting.reset_run_totals!
  end

  CELLS.each do |cell, (setup, expectations)|
    expectations.each do |mode, expected|
      test "record: :#{mode} with a capture that is #{cell}" do
        outcome = run_cell(mode, *setup)

        assert_equal expected[:status], outcome.assertion.status
        assert_equal expected[:raises], outcome.raised, "raise"
        assert_equal expected.values_at(:verified, :changed, :rerecorded, :new),
          [SnapDiff::Reporting.verified, SnapDiff::Reporting.changed, outcome.rerecorded_count, SnapDiff::Reporting.missing_baselines_count]
        assert_equal [expected[:entry]].compact, outcome.entries.map { |entry| entry["status"] }, "report entries"

        assert_files(cell, mode, outcome)
      end
    end
  end

  private

  Outcome = Struct.new(:assertion, :raised, :entries, :rerecorded_count, :snap_path, :base_path, :committed)

  # Drives the matcher the way the DSL does, then the end of the test: verify
  # (which is where a delayed failure raises), tally, report.
  def run_cell(mode, baseline, capture, options)
    SnapDiff.config.record = mode
    raised = false
    snap = baseline ? create_snapshot_for(baseline, capture) : @manager.snapshot("a_#{Time.now.nsec}")
    committed = baseline && snap.base_path.binread

    capture_io do
      SnapDiff::Vcs.stub(:checkout_vcs, !baseline.nil?) do
        SnapDiff::ScreenshotMatcher.new(snap.full_name, **options).build_screenshot_assertion
        SnapDiff.session.verify
      rescue SnapDiff::ExpectationNotMet
        raised = true
      end
    end

    assertions = SnapDiff.session.assertions
    SnapDiff::Reporting.count(assertions)
    reporter = SnapDiff::Reporters::HTML.new(output_path: Pathname(@new_root) / "report.html")
    reporter.record(assertions)

    Outcome.new(assertions.sole, raised, reporter.entries.map { |e| e.transform_keys(&:to_s) },
      reporter.rerecorded_count, snap.path, snap.base_path, committed)
  end

  # The files a run leaves behind: the capture is always there; the committed
  # bytes come back for a pass (no `.base` left over); a difference leaves
  # the baseline beside the capture, and the capture stays where it is.
  def assert_files(cell, mode, outcome)
    assert_predicate outcome.snap_path, :exist?, "the capture is always on disk"

    if outcome.assertion.status == :passed
      assert_not_predicate outcome.base_path, :exist?, "a match leaves no .base file"
      assert_equal outcome.committed, outcome.snap_path.binread, "the committed bytes are restored" if cell == "within tolerance"
    elsif outcome.assertion.status != :new
      assert_equal outcome.committed, outcome.base_path.binread, "the baseline is kept beside the capture"
      assert_not_equal outcome.committed, outcome.snap_path.binread, "the capture is what is left to `git add`" if mode == :all
    end
  end
end
