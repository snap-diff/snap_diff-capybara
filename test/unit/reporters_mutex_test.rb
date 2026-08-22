# frozen_string_literal: true

require "test_helper"

module CapybaraScreenshotDiff
  class ReportersMutexTest < ActiveSupport::TestCase
    setup do
      @original_reporters = CapybaraScreenshotDiff.reporters.dup
      CapybaraScreenshotDiff.reporters.clear
    end

    teardown do
      CapybaraScreenshotDiff.reporters.clear
      CapybaraScreenshotDiff.reporters.concat(@original_reporters)
    end

    test "reporters_mutex is eagerly initialized" do
      assert_instance_of Mutex, CapybaraScreenshotDiff.reporters_mutex
    end

    test "reporters_mutex returns the same instance" do
      assert_same CapybaraScreenshotDiff.reporters_mutex, CapybaraScreenshotDiff.reporters_mutex
    end

    # ADR-008 step 6: SnapDiff::Reporting.register is the canonical way in;
    # CapybaraScreenshotDiff.reporters stays as the compat view of the same
    # array, so a registration must be visible through both.
    test "register appends to the array CapybaraScreenshotDiff.reporters exposes" do
      reporter = Object.new

      assert_same reporter, SnapDiff::Reporting.register(reporter)
      assert_same SnapDiff::Reporting.reporters, CapybaraScreenshotDiff.reporters
      assert_includes CapybaraScreenshotDiff.reporters, reporter
    end

    # Best-effort probe: MRI's GVL can make an unsynchronized Array#<< look
    # safe, so a green run here is not proof. The mutex in .register is the
    # actual defense (issue #217 item 2); this pins that no registration is
    # dropped under contention.
    test "concurrent register calls retain every reporter" do
      reporters = 32.times.map { Object.new }

      reporters.map { |reporter| Thread.new { SnapDiff::Reporting.register(reporter) } }.each(&:join)

      assert_equal reporters.size, SnapDiff::Reporting.reporters.size
      assert_empty reporters - SnapDiff::Reporting.reporters
    end

    test "reporters notification iterates over snapshot" do
      received = []

      mutating_reporter = Class.new do
        define_method :record do |assertions|
          received << [:original, assertions]
          CapybaraScreenshotDiff.reporters.clear
          CapybaraScreenshotDiff.reporters << Class.new {
            define_method(:record) { |a| received << [:added, a] }
          }.new
        end
      end.new

      CapybaraScreenshotDiff.reporters << mutating_reporter

      assertions = [:some, :assertions]

      assert_nothing_raised do
        CapybaraScreenshotDiff.send(:notify_reporters, assertions)
      end

      assert_equal [[:original, assertions]], received
    end
  end
end
