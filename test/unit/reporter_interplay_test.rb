# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff"

module CapybaraScreenshotDiff
  # Guard #4 from the v2 core-redesign acceptance contract.
  #
  # Reporter tests used to exercise the wrong seam (reporter.record called
  # with hand-built arrays). This pins the real wiring: a delayed
  # assert_matches_screenshot lands in the registry, CapybaraScreenshotDiff.reset
  # notifies registered reporters BEFORE clearing the registry, and
  # finalize_reporters! drives finalize/summary.
  class ReporterInterplayTest < ActiveSupport::TestCase
    include SnapDiff::DSL
    include CapybaraScreenshotDiff::DSLStub

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
      CapybaraScreenshotDiff.reporters_mutex.synchronize do
        @original_reporters = CapybaraScreenshotDiff.reporters.dup
        CapybaraScreenshotDiff.reporters.clear
        CapybaraScreenshotDiff.reporters << @spy
      end
    end

    teardown do
      CapybaraScreenshotDiff.reporters_mutex.synchronize do
        CapybaraScreenshotDiff.reporters.clear
        CapybaraScreenshotDiff.reporters.concat(@original_reporters)
      end
    end

    test "a delayed assertion reaches registered reporters through the real reset path" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :a)

        assert_matches_screenshot(snap.full_name) # delayed by default
        assert_predicate CapybaraScreenshotDiff.registry, :assertions_present?

        CapybaraScreenshotDiff.reset

        assert_equal 1, @spy.recorded.size, "reset must notify reporters with the pending assertions"
        recorded_assertions = @spy.recorded.first
        assert_equal [snap.full_name], recorded_assertions.map(&:name)

        assert_not_predicate CapybaraScreenshotDiff.registry, :assertions_present?,
          "reset must clear the registry only after reporters were notified"
      end
    end

    test "reset without assertions does not notify reporters" do
      CapybaraScreenshotDiff.reset

      assert_empty @spy.recorded
    end

    test "finalize_reporters! finalizes each reporter and prints its summary" do
      assert_output(/spy reporter summary/) do
        CapybaraScreenshotDiff.finalize_reporters!
      end

      assert @spy.finalized
    end

    class RaisingReporter
      def record(_assertions) = raise "record boom"

      def finalize = raise "finalize boom"

      def summary = nil
    end

    test "a raising reporter during reset warns and does not stop other reporters" do
      CapybaraScreenshotDiff.reporters_mutex.synchronize do
        CapybaraScreenshotDiff.reporters.unshift(RaisingReporter.new)
      end

      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :a)
        assert_matches_screenshot(snap.full_name)

        _out, err = capture_io { CapybaraScreenshotDiff.reset }

        assert_match(/Reporter failed: record boom/, err)
        assert_equal 1, @spy.recorded.size, "reporters after the raising one must still be notified"
      end
    end

    test "a raising reporter during finalize_reporters! warns and does not stop other reporters" do
      CapybaraScreenshotDiff.reporters_mutex.synchronize do
        CapybaraScreenshotDiff.reporters.unshift(RaisingReporter.new)
      end

      _out, err = capture_io { CapybaraScreenshotDiff.finalize_reporters! }

      assert_match(/RaisingReporter failed \(RuntimeError: finalize boom\)/, err)
      assert @spy.finalized, "reporters after the raising one must still be finalized"
    end
  end
end
