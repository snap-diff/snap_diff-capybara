# frozen_string_literal: true

require "test_helper"
require "snap_diff"

# The end-of-run counts, unit-sized. Their home is SnapDiff::Reporting, not
# a reporter (issue #269): counting is core honesty, writing an HTML file is
# a feature, and the summary exists to catch what no per-assertion rule can
# see -- a run where zero system tests executed, or where an inherited
# GIT_DIR redirected every baseline lookup.
#
# That the line actually reaches a real run's stdout with no reporter
# registered is asserted where it can only be asserted, on a finished
# process: test/integration/summary_line_test.rb.
class ReportingCountsTest < ActiveSupport::TestCase
  include DSLStub

  # No reporter registered here on purpose: the counts must not depend on one.
  setup do
    SnapDiff::Reporting.mutex.synchronize do
      @original_reporters = SnapDiff::Reporting.reporters.dup
      SnapDiff::Reporting.reporters.clear
    end
  end

  teardown do
    SnapDiff::Reporting.mutex.synchronize do
      SnapDiff::Reporting.reporters.clear
      SnapDiff::Reporting.reporters.concat(@original_reporters)
    end
  end

  test "counts what was verified, what changed, and what was never compared" do
    SnapDiff::Reporting.record_missing_baseline("never_compared")
    SnapDiff::Reporting.notify([build_passing_assertion("ok"), build_failing_assertion("fail")])

    assert_equal "[snap_diff] 2 verified, 1 changed, 1 new (not verified).",
      SnapDiff::Reporting.counts_summary
  end

  test "counts every changed screenshot, not just the first" do
    SnapDiff::Reporting.notify([build_failing_assertion("first"), build_failing_assertion("second")])

    assert_includes SnapDiff::Reporting.counts_summary, "2 verified, 2 changed"
  end

  test "counts accumulate across tests" do
    SnapDiff::Reporting.notify([build_passing_assertion("one")])
    SnapDiff::Reporting.notify([build_failing_assertion("two")])

    assert_includes SnapDiff::Reporting.counts_summary, "2 verified, 1 changed"
  end

  # Zero verified is the whole tell for the failure modes no assertion can
  # report: a suite that ran no system tests at all, or one whose baseline
  # lookup was redirected to another repository. The line must never be nil
  # and must not read like a pass.
  test "shouts when nothing was verified" do
    assert_equal "[snap_diff] 0 verified, 0 changed, 0 new (not verified). " \
      "NOTHING WAS VERIFIED -- no screenshot was compared to a committed baseline.",
      SnapDiff::Reporting.counts_summary
  end

  # `record: :all` (#274) re-records without comparing, so those screenshots
  # are neither verified nor changed -- and they are not "new" either, which
  # is a different fact with its own line. The counts line has to say what
  # happened, and must NOT cry NOTHING WAS VERIFIED at a user who asked for
  # exactly this: a false alarm here trains people to ignore the real one.
  test "re-recorded screenshots are counted, and explain a zero verified" do
    SnapDiff::Reporting.record_rerecorded_baseline("a")
    SnapDiff::Reporting.record_rerecorded_baseline("b")

    summary = SnapDiff::Reporting.counts_summary

    assert_includes summary, "0 verified, 0 changed, 0 new (not verified)."
    assert_includes summary, "2 re-recorded"
    refute_includes summary, "NOTHING WAS VERIFIED"
  end

  # The shout is for an UNEXPLAINED zero -- that is the whole point of it.
  test "a zero verified with nothing re-recorded still shouts" do
    assert_includes SnapDiff::Reporting.counts_summary, "NOTHING WAS VERIFIED"
  end

  # `record:` is a per-screenshot option too, so a run can mix both.
  test "a run that verified some and re-recorded others reports both" do
    SnapDiff::Reporting.notify([build_passing_assertion("ok")])
    SnapDiff::Reporting.record_rerecorded_baseline("accepted")

    summary = SnapDiff::Reporting.counts_summary

    assert_includes summary, "1 verified, 0 changed, 0 new (not verified)."
    assert_includes summary, "1 re-recorded"
  end

  test "counts screenshots captured with no committed baseline even when nothing was verified" do
    SnapDiff::Reporting.record_missing_baseline("a")
    SnapDiff::Reporting.record_missing_baseline("b")

    assert_includes SnapDiff::Reporting.counts_summary, "0 verified, 0 changed, 2 new (not verified)."
  end

  # The reason this moved: the gem's one and only `register` call site is in
  # reporters/html.rb, so the documented Rails setup registers nothing.
  test "finalize! prints the counts with no reporter registered" do
    SnapDiff::Reporting.notify([build_passing_assertion("ok")])

    out, _err = capture_io { SnapDiff::Reporting.finalize! }

    assert_empty SnapDiff::Reporting.reporters
    assert_includes out, "[snap_diff] 1 verified, 0 changed, 0 new (not verified)."
  end

  test "an assertion with no comparison is neither verified nor changed" do
    SnapDiff::Reporting.notify([SnapDiff::ScreenshotAssertion.new("never_compared")])

    assert_includes SnapDiff::Reporting.counts_summary, "0 verified, 0 changed"
  end

  private

  def build_passing_assertion(name)
    build_assertion(name, :a, :a, "pass")
  end

  def build_failing_assertion(name)
    build_assertion(name, :a, :b, "fail")
  end

  def build_assertion(name, base, new, prefix)
    compare = make_comparison(base, new, destination: "#{prefix}_#{name}")
    compare.processed

    SnapDiff::ScreenshotAssertion.new(name).tap { |assertion| assertion.compare = compare }
  end
end
