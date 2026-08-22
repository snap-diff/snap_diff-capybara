# frozen_string_literal: true

require "fileutils"

module CapybaraScreenshotDiff
  class ScreenshotAssertion
    attr_reader :name, :args
    attr_accessor :compare, :caller

    def initialize(name, **args)
      @name = name
      @args = args
    end

    def validate
      return unless compare

      self.class.assert_image_not_changed(caller, name, compare)
    end

    def validate!
      error_msg = validate

      if error_msg
        raise CapybaraScreenshotDiff::ExpectationNotMet.new(error_msg, caller)
      end
    end

    # Verifies that all scheduled screenshots do not show any unintended differences.
    #
    # @param screenshots [Array(Array(Array(String), String, ImageCompare))] The list of match screenshots jobs. Defaults to all screenshots taken during the test.
    # @return [Array, nil] Returns an array of error messages if there are screenshot differences, otherwise nil.
    # @note This method is typically called at the end of a test to assert all screenshots are as expected.
    def self.verify_screenshots!(screenshots)
      return unless ::Capybara::Screenshot.active? && ::Capybara::Screenshot::Diff.fail_on_difference

      test_screenshot_errors = screenshots.map do |assertion|
        assertion.validate
      end

      test_screenshot_errors.compact!

      test_screenshot_errors.empty? ? nil : test_screenshot_errors
    end

    # Asserts that an image has not changed compared to its baseline.
    #
    # @param backtrace [Array(String)] The caller context, used for error reporting.
    # @param name [String] The name of the screenshot being verified.
    # @param comparison [Object] The comparison object containing the result and details of the comparison.
    # @return [String, nil] Returns an error message if the screenshot differs from the baseline, otherwise nil.
    # @note This method is used internally to verify individual screenshots.
    def self.assert_image_not_changed(backtrace, name, comparison)
      result = comparison.different?

      # Cleanup after comparisons
      if !result && comparison.base_image_path.exist?
        FileUtils.mv(comparison.base_image_path, comparison.image_path, force: true)
      end

      return unless result

      "Screenshot does not match for '#{name}': #{comparison.error_message}\n#{backtrace.join("\n")}"
    end
  end

  class AssertionRegistry
    attr_reader :assertions, :screenshot_namer, :new_screenshots

    def initialize
      @assertions = []
      @new_screenshots = []
      @screenshot_namer = CapybaraScreenshotDiff::ScreenshotNamer.new
    end

    def add_assertion(assertion)
      return unless assertion&.compare

      @assertions.push(assertion)

      assertion
    end

    def assertions_present?
      !@assertions.empty?
    end

    def record_new_screenshot(name)
      @new_screenshots.push(name)
    end

    def new_screenshots_present?
      !@new_screenshots.empty?
    end

    def verify(screenshots = CapybaraScreenshotDiff.assertions)
      return unless ::Capybara::Screenshot.active? && ::Capybara::Screenshot::Diff.fail_on_difference

      failed_assertions = CapybaraScreenshotDiff.registry.failed_assertions
      failed_screenshot = failed_assertions.first
      result = ScreenshotAssertion.verify_screenshots!(screenshots)

      if result
        raise CapybaraScreenshotDiff::ExpectationNotMet.new(result.join("\n\n"), failed_screenshot.caller)
      end
    end

    def failed_assertions
      assertions.filter { |screenshot_assert| screenshot_assert.compare&.different? }
    end

    def reset
      @assertions.clear
      @new_screenshots.clear
      @screenshot_namer = CapybaraScreenshotDiff::ScreenshotNamer.new
    end
  end
end

module CapybaraScreenshotDiff
  class << self
    require "forwardable"
    extend Forwardable

    def registry
      Thread.current[:capybara_screenshot_diff_registry] ||= AssertionRegistry.new
    end

    def_delegator :registry, :add_assertion
    def_delegator :registry, :assertions
    def_delegator :registry, :assertions_present?
    def_delegator :registry, :failed_assertions
    def_delegator :registry, :record_new_screenshot
    def_delegator :registry, :new_screenshots
    def_delegator :registry, :new_screenshots_present?
    def reset
      notify_reporters(registry.assertions)
      registry.reset
    end

    def reporters
      @reporters ||= []
    end

    attr_reader :reporters_mutex

    def finalize_reporters!
      reporters_mutex.synchronize { reporters.dup }.each do |reporter|
        reporter.finalize
        if (msg = reporter.summary)
          $stdout.puts msg
        end
      rescue => e
        warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})"
      end
    end

    def_delegator :registry, :screenshot_namer
    def_delegator :registry, :verify

    private

    def notify_reporters(assertions)
      return if assertions.nil? || assertions.empty?

      reporters_snapshot = reporters_mutex.synchronize { reporters.dup }
      return if reporters_snapshot.empty?

      reporters_snapshot.each do |reporter|
        reporter.record(assertions)
      rescue => e
        warn "[capybara-screenshot-diff] Reporter failed: #{e.message}"
      end
    end
  end

  @reporters_mutex = Mutex.new
end
