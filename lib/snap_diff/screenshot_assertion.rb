# frozen_string_literal: true

require "fileutils"
require_relative "screenshot_namer"
require_relative "reporting"

module SnapDiff
  # --- Session lifecycle (per-test) ---
  #
  # The canonical home of the per-test session: the AssertionRegistry
  # holding the assertions and new-screenshot names of the test running
  # here. CapybaraScreenshotDiff.registry / .reset /
  # .pending_screenshots_message are thin forwarders over these.
  #
  # Note: Thread.current[] is *fiber*-local, so a session is per fiber, not
  # per thread. That is pre-existing, documented behaviour (issue #217);
  # ADR-008 step 6 relocates the accessor without touching the semantics.
  def self.session
    Thread.current[:capybara_screenshot_diff_registry] ||= AssertionRegistry.new
  end

  # Ends a test: hands the finished session's assertions to the reporters,
  # then clears it. The one deliberate bridge between the process-global
  # reporter lifecycle (SnapDiff::Reporting) and the per-test session.
  def self.reset
    Reporting.notify(session.assertions)
    session.reset
  end

  # Message to skip the test with when a new screenshot has no baseline yet
  # and `pending_if_new` is enabled. Adapters call this after verifying
  # screenshots, and skip the test with the returned message when present.
  #
  # @return [String, nil] the pending message, or nil when there is nothing to report
  def self.pending_screenshots_message
    return unless ::Capybara::Screenshot::Diff.pending_if_new && session.new_screenshots_present?

    "No baseline for: #{session.new_screenshots.join(", ")}. Commit the captured screenshots to record them."
  end

  class ScreenshotAssertion
    attr_reader :name, :args
    attr_accessor :compare, :caller

    def initialize(name, **args)
      @name = name
      @args = args
    end

    # One-line debugging summary. Never triggers the (expensive, file-touching)
    # comparison itself: an unprocessed comparison shows as "pending".
    def inspect
      return "#<#{self.class.name} #{name.inspect} (no comparison)>" unless compare

      state = if compare.processed?
        compare.difference.different? ? "different" : "matches"
      else
        "pending"
      end
      "#<#{self.class.name} #{name.inspect} #{state} new=#{compare.image_path} base=#{compare.base_image_path}>"
    end

    def validate
      return unless compare

      if compare.different?
        "Screenshot does not match for '#{name}': #{compare.error_message}\n#{caller.join("\n")}"
      else
        archive_baseline!
        nil
      end
    end

    # Commits the baseline after a passing comparison: the base image is
    # moved over the actual image, so the captured screenshot becomes the
    # recorded baseline again. This is the file-mutating half of the verify
    # flow, kept explicit and separate from the pure "are they different?"
    # question. Idempotent: a second call is a no-op.
    def archive_baseline!
      return unless compare && !compare.different? && compare.base_image_path.exist?

      FileUtils.mv(compare.base_image_path, compare.image_path, force: true)
    end

    def validate!
      error_msg = validate

      if error_msg
        raise SnapDiff::ExpectationNotMet.new(error_msg, caller)
      end
    end

    # Verifies that all scheduled screenshots do not show any unintended differences.
    #
    # @param screenshots [Array(Array(Array(String), String, Comparison))] The list of match screenshots jobs. Defaults to all screenshots taken during the test.
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
    # @note Legacy entry point; delegates to the instance verify flow
    #   (pure question + explicit #archive_baseline! on pass).
    def self.assert_image_not_changed(backtrace, name, comparison)
      assertion = new(name)
      assertion.caller = backtrace
      assertion.compare = comparison
      assertion.validate
    end
  end

  class AssertionRegistry
    attr_reader :assertions, :screenshot_namer, :new_screenshots

    def initialize
      @assertions = []
      @new_screenshots = []
      @screenshot_namer = SnapDiff::ScreenshotNamer.new
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

    def verify(screenshots = assertions)
      return unless ::Capybara::Screenshot.active? && ::Capybara::Screenshot::Diff.fail_on_difference

      failed_screenshot = failed_assertions.first
      result = ScreenshotAssertion.verify_screenshots!(screenshots)

      if result
        raise SnapDiff::ExpectationNotMet.new(result.join("\n\n"), failed_screenshot.caller)
      end
    end

    def failed_assertions
      assertions.filter { |screenshot_assert| screenshot_assert.compare&.different? }
    end

    def reset
      @assertions.clear
      @new_screenshots.clear
      @screenshot_namer = SnapDiff::ScreenshotNamer.new
    end
  end
end
