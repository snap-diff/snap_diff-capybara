# frozen_string_literal: true

require "fileutils"

module CapybaraScreenshotDiff
  class ScreenshotAssertion
    attr_reader :name, :args
    attr_accessor :compare, :caller

    def initialize(name, **args, &block)
      @name = name
      @args = args

      yield(self) if block_given?
    end

    def self.from(screenshot_job)
      return screenshot_job if screenshot_job.is_a?(ScreenshotAssertion)

      caller, name, compare = screenshot_job
      ScreenshotAssertion.new(name).tap do |it|
        it.caller = caller
        it.compare = compare
      end
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
    ensure
      screenshots&.clear
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
      elsif !comparison.dimensions_changed?
        FileUtils.rm_rf(comparison.base_image_path)
      end

      return unless result

      "Screenshot does not match for '#{name}': #{comparison.error_message}\n#{backtrace.join("\n")}"
    end
  end

  class AssertionRegistry
    attr_reader :assertions, :screenshot_namer

    def initialize
      @assertions = []
      @screenshot_namer = CapybaraScreenshotDiff::ScreenshotNamer.new
    end

    def add_assertion(assertion)
      assertion = ScreenshotAssertion.from(assertion)
      return unless assertion.compare

      @assertions.push(assertion)

      assertion
    end

    def assertions_present?
      !@assertions.empty?
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
    def_delegator :registry, :reset
    def_delegator :registry, :screenshot_namer
    def_delegator :registry, :verify
  end
end
