# frozen_string_literal: true

require "capybara_screenshot_diff"
require "capybara/screenshot/diff/drivers"
require "capybara/screenshot/diff/image_compare"
require "capybara/screenshot/diff/screenshot_matcher"
require "capybara/screenshot/diff/screenshot_namer_dsl"
require "capybara_screenshot_diff/screenshot_assertion"

module CapybaraScreenshotDiff
  # DSL for taking screenshots and making assertions
  # Provides methods for screenshot naming, organization, and validation
  module DSL
    include Capybara::DSL
    include Capybara::Screenshot::Diff::ScreenshotNamerDSL

    # Takes a screenshot and optionally compares it against a baseline image.
    #
    # @param name [String] The name of the screenshot, used to generate the filename.
    # @param skip_stack_frames [Integer] The number of stack frames to skip when reporting errors.
    # @param options [Hash] Additional options for taking the screenshot and comparison.
    # @option options [Boolean] :delayed Whether to validate the screenshot immediately or delay.
    # @option options [String, Array<Integer>] :crop Area to crop the screenshot to.
    # @option options [Array] :skip_area Areas to ignore during comparison.
    # @return [Boolean] True if the screenshot was successfully captured and processed.
    # @raise [CapybaraScreenshotDiff::ExpectationNotMet] If comparison fails and immediate validation.
    def screenshot(name, skip_stack_frames: 0, **options)
      return false unless Capybara::Screenshot.active?

      # Get the full name with section and group information
      full_name = CapybaraScreenshotDiff.screenshot_namer.full_name(name)

      # Build the screenshot assertion
      assertion = build_screenshot_assertion(full_name, options, skip_stack_frames: skip_stack_frames + 1)

      return false unless assertion

      # Determine if validation should be delayed or immediate
      delayed = options.fetch(:delayed, Capybara::Screenshot::Diff.delayed)

      if delayed
        CapybaraScreenshotDiff.add_assertion(assertion)
      else
        assertion.validate!
      end

      true
    end

    # Creates an alias for backward compatibility
    alias_method :assert_matches_screenshot, :screenshot

    private

    # Builds a screenshot assertion object that can be validated immediately or later
    #
    # @param name [String] The full name of the screenshot
    # @param options [Hash] Options for screenshot taking and comparison
    # @param skip_stack_frames [Integer] Stack frames to skip for error reporting
    # @return [ScreenshotAssertion, nil] The assertion object or nil if it's not required
    def build_screenshot_assertion(name, options, skip_stack_frames: 0)
      Capybara::Screenshot::Diff::ScreenshotMatcher
        .new(name, options)
        .build_screenshot_assertion(skip_stack_frames: skip_stack_frames + 1)
    end
  end
end
