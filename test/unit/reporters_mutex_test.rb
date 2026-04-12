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
