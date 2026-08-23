# frozen_string_literal: true

require "test_helper"

class ReportersMutexTest < ActiveSupport::TestCase
  setup do
    @original_reporters = SnapDiff::Reporting.reporters.dup
    SnapDiff::Reporting.reporters.clear
  end

  teardown do
    SnapDiff::Reporting.reporters.clear
    SnapDiff::Reporting.reporters.concat(@original_reporters)
  end

  test "reporters_mutex is eagerly initialized" do
    assert_instance_of Mutex, SnapDiff::Reporting.mutex
  end

  test "reporters_mutex returns the same instance" do
    assert_same SnapDiff::Reporting.mutex, SnapDiff::Reporting.mutex
  end

  # ADR-008 step 6: SnapDiff::Reporting.register is the canonical way in,
  # and it returns the reporter it registered.
  # (That the v1 CapybaraScreenshotDiff.reporters view is the SAME array is
  # pinned in test/legacy/legacy_forwarders_test.rb.)
  test "register appends to the array SnapDiff::Reporting.reporters exposes" do
    reporter = Object.new

    assert_same reporter, SnapDiff::Reporting.register(reporter)
    assert_includes SnapDiff::Reporting.reporters, reporter
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
        SnapDiff::Reporting.reporters.clear
        SnapDiff::Reporting.reporters << Class.new {
          define_method(:record) { |a| received << [:added, a] }
        }.new
      end
    end.new

    SnapDiff::Reporting.reporters << mutating_reporter

    assertions = [:some, :assertions]

    assert_nothing_raised do
      CapybaraScreenshotDiff.send(:notify_reporters, assertions)
    end

    assert_equal [[:original, assertions]], received
  end
end
