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
      CapybaraScreenshotDiff.instance_variable_set(:@reporters_mutex, nil)
    end

    test "reporters notification uses mutex snapshot" do
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

      CapybaraScreenshotDiff.instance_variable_set(:@reporters_mutex, fake_mutex)

      reporter = Class.new do
        def record(_assertions); end
      end.new

      CapybaraScreenshotDiff.reporters << reporter

      assertion = CapybaraScreenshotDiff::ScreenshotAssertion.new("sample")
      assertion.compare = Object.new
      CapybaraScreenshotDiff.add_assertion(assertion)

      CapybaraScreenshotDiff.reset

      assert_operator fake_mutex.synchronize_calls, :>=, 1
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
