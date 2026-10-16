# frozen_string_literal: true

require "test_helper"
require "snap_diff"

# Guard #4 from the v2 core-redesign acceptance contract.
#
# Reporter tests used to exercise the wrong seam (reporter.record called
# with hand-built arrays). This pins the real wiring: a delayed
# assert_matches_screenshot lands in the registry, SnapDiff.reset
# notifies registered reporters BEFORE clearing the registry, and
# finalize_reporters! drives finalize/summary.
class ReporterInterplayTest < ActiveSupport::TestCase
  include SnapDiff::DSL
  include DSLStub

  class SpyReporter
    attr_reader :recorded, :finalized

    def initialize
      @recorded = []
      @finalized = false
    end

    def record(assertions)
      @recorded << assertions.dup
    end

    def finalize
      @finalized = true
    end

    def summary
      "spy reporter summary"
    end
  end

  setup do
    @spy = SpyReporter.new
    SnapDiff::Reporting.mutex.synchronize do
      @original_reporters = SnapDiff::Reporting.reporters.dup
      SnapDiff::Reporting.reporters.clear
      SnapDiff::Reporting.reporters << @spy
    end
  end

  teardown do
    SnapDiff::Reporting.mutex.synchronize do
      SnapDiff::Reporting.reporters.clear
      SnapDiff::Reporting.reporters.concat(@original_reporters)
    end
  end

  test "a delayed assertion reaches registered reporters through the real reset path" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :a)

      assert_matches_screenshot(snap.full_name) # delayed by default
      assert_predicate SnapDiff.session, :assertions_present?

      SnapDiff.reset

      assert_equal 1, @spy.recorded.size, "reset must notify reporters with the pending assertions"
      recorded_assertions = @spy.recorded.first
      assert_equal [snap.full_name], recorded_assertions.map(&:name)

      assert_not_predicate SnapDiff.session, :assertions_present?,
        "reset must clear the registry only after reporters were notified"
    end
  end

  # The same wiring for the immediate path. An assertion validated with
  # delayed: false is just as finished as a delayed one; a suite that runs
  # that way used to end on "0 verified" with its failures missing from
  # the report.
  test "an immediate assertion reaches reporters and the tally too" do
    SnapDiff::Reporting.reset_run_totals!
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :a)

      assert_matches_screenshot(snap.full_name, delayed: false)
      SnapDiff.reset

      assert_equal [snap.full_name], @spy.recorded.flatten.map(&:name)
      assert_equal 1, SnapDiff::Reporting.verified
    end
  end

  test "an immediate failure is reported once and raised once" do
    SnapDiff::Reporting.reset_run_totals!
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:c, :a)

      assert_raises(SnapDiff::ExpectationNotMet) { assert_matches_screenshot(snap.full_name, delayed: false) }
      assert_nil SnapDiff.session.verify, "teardown must not fail the test a second time"
      SnapDiff.reset

      assert_equal [snap.full_name], @spy.recorded.flatten.map(&:name)
      assert_equal 1, SnapDiff::Reporting.changed
    end
  end

  # A comparison nobody ran has no verdict yet. With fail_on_difference
  # off, teardown never validates, so the tally has to force the comparison
  # itself or it reports a differing screenshot as verified and matching.
  test "the tally runs a comparison nobody forced" do
    SnapDiff::Reporting.reset_run_totals!
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff.config.stub(:fail_on_difference, false) do
        differing = create_snapshot_for(:c, :a)
        matching = create_snapshot_for(:a, :a)

        assert_matches_screenshot(differing.full_name)
        assert_matches_screenshot(matching.full_name)
        assert_nil SnapDiff.session.verify, "fail_on_difference = false never fails the test"
        SnapDiff.reset

        assert_equal 2, SnapDiff::Reporting.verified
        assert_equal 1, SnapDiff::Reporting.changed
      end
    end
  end

  # A comparison that blows up costs its own row, not the test's whole tally:
  # the other screenshots of the same test still count, and the warning names
  # the one that failed.
  test "a comparison that raises is skipped on its own, with a warning naming it" do
    SnapDiff::Reporting.reset_run_totals!
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      good = create_snapshot_for(:a, :a)
      assert_matches_screenshot(good.full_name)

      broken = SnapDiff::ScreenshotAssertion.new("broken_shot")
      broken.compare = Object.new.tap { |compare| compare.define_singleton_method(:different?) { raise "boom" } }
      SnapDiff.session.add_assertion(broken)

      _out, err = capture_io { SnapDiff.reset }

      assert_equal 1, SnapDiff::Reporting.verified
      assert_match(/Could not tally 'broken_shot' \(RuntimeError: boom\)/, err)
      assert_equal 2, @spy.recorded.flatten.size, "reporters still get every assertion"
    end
  end

  # Nothing the tally does on a healthy run, or on a capture that vanished
  # before it was compared, is worth a line on stderr.
  test "reset tallies a match, a difference and a vanished capture without a word" do
    SnapDiff::Reporting.reset_run_totals!
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      matching = create_snapshot_for(:a, :a)
      differing = create_snapshot_for(:c, :a)
      vanished = create_snapshot_for(:c, :a)
      [matching, differing, vanished].each { |snap| assert_matches_screenshot(snap.full_name) }
      FileUtils.rm(vanished.path)

      _out, err = capture_io { SnapDiff.reset }

      assert_empty err
      assert_equal 3, SnapDiff::Reporting.verified
      assert_equal 2, SnapDiff::Reporting.changed
    end
  end

  test "reporters receive a new screenshot as a :new assertion with no comparison" do
    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      capture_io { screenshot("a") }
      SnapDiff.reset
    end

    received = @spy.recorded.flatten
    assert_equal [["a", :new]], received.map { |a| [a.name, a.status] }
    assert_nil received.first.compare
  end

  test "reset without assertions does not notify reporters" do
    SnapDiff.reset

    assert_empty @spy.recorded
  end

  # The reporters count what WAS compared, so their summary is silent about
  # the screenshots that passed without being looked at. The last line of the
  # run has to name them, or a run full of false greens ends on
  # "no failures".
  test "finalize! names the screenshots that had no committed baseline" do
    # ScreenshoterStub resolves "c_<digits>" to the c.png fixture.
    name = "c_#{Time.now.nsec}"

    capture_io do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
      end
    end

    out, _err = capture_io { SnapDiff::Reporting.finalize! }

    assert_match(/no committed baseline/i, out)
    assert_match(/NOT compared/, out)
    assert_includes out, name
  end

  test "finalize! says nothing about baselines when every screenshot had one" do
    out, _err = capture_io { SnapDiff::Reporting.finalize! }

    assert_no_match(/no committed baseline/i, out)
  end

  test "finalize_reporters! finalizes each reporter and prints its summary" do
    assert_output(/spy reporter summary/) do
      SnapDiff::Reporting.finalize!
    end

    assert @spy.finalized
  end

  class RaisingReporter
    def record(_assertions) = raise "record boom"

    def finalize = raise "finalize boom"

    def summary = nil
  end

  test "a raising reporter during reset warns and does not stop other reporters" do
    SnapDiff::Reporting.mutex.synchronize do
      SnapDiff::Reporting.reporters.unshift(RaisingReporter.new)
    end

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :a)
      assert_matches_screenshot(snap.full_name)

      _out, err = capture_io { SnapDiff.reset }

      assert_match(/\[snap_diff\] Reporter \S*RaisingReporter failed \(RuntimeError: record boom\)/, err)
      assert_equal 1, @spy.recorded.size, "reporters after the raising one must still be notified"
    end
  end

  test "a raising reporter during finalize_reporters! warns and does not stop other reporters" do
    SnapDiff::Reporting.mutex.synchronize do
      SnapDiff::Reporting.reporters.unshift(RaisingReporter.new)
    end

    _out, err = capture_io { SnapDiff::Reporting.finalize! }

    assert_match(/RaisingReporter failed \(RuntimeError: finalize boom\)/, err)
    assert @spy.finalized, "reporters after the raising one must still be finalized"
  end
end
