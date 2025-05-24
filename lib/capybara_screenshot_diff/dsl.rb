# frozen_string_literal: true

require "capybara_screenshot_diff"
require "capybara/screenshot/diff/drivers"
require "capybara/screenshot/diff/image_compare"
require "capybara/screenshot/diff/screenshot_matcher"
require "capybara/screenshot/diff/screenshot_namer_dsl"
require "capybara_screenshot_diff/screenshot_assertion"

module CapybaraScreenshotDiff
  # DSL for taking screenshots and making assertions in Capybara tests.
  # This module provides methods for taking screenshots, comparing them against baselines,
  # and managing the comparison process with various configuration options.
  #
  # The DSL is designed to be included in your test context (e.g., RSpec, Minitest)
  # to provide screenshot comparison capabilities.
  module DSL
    include Capybara::DSL
    include Capybara::Screenshot::Diff::ScreenshotNamerDSL

    # Takes a screenshot and optionally compares it against a baseline image.
    #
    # The method follows a layered optimization strategy for comparison:
    # 1. First checks if screenshot functionality is active
    # 2. Builds a full screenshot name using the current context
    # 3. Creates a screenshot assertion object
    # 4. Either validates immediately or defers validation based on options
    #
    # @param name [String] The base name of the screenshot, used to generate the filename.
    # @param skip_stack_frames [Integer] The number of stack frames to skip when reporting errors.
    # @param options [Hash] Additional options for taking the screenshot and comparison.
    # @option options [Boolean] :delayed (Capybara::Screenshot::Diff.delayed)
    #   Whether to validate the screenshot immediately or delay validation.
    # @option options [Array<Integer>] :crop [x, y, width, height] Area to crop the screenshot to.
    # @option options [Array<Array<Integer>>] :skip_area Array of [x, y, width, height] areas to ignore.
    # @option options [Numeric] :tolerance (0.001 for :vips driver) Color tolerance for comparison.
    # @option options [Numeric] :color_distance_limit Maximum allowed color distance between pixels.
    # @option options [Numeric] :shift_distance_limit Maximum allowed shift distance for pixels.
    # @option options [Numeric] :area_size_limit Maximum allowed difference area size in pixels.
    # @option options [Symbol] :driver (:auto) The image processing driver to use (:auto, :chunky_png, :vips).
    # @return [Boolean] True if the screenshot was successfully captured and processed.
    # @raise [CapybaraScreenshotDiff::ExpectationNotMet] If comparison fails and immediate validation is enabled.
    # @raise [CapybaraScreenshotDiff::UnstableImage] If the image comparison is unstable.
    # @raise [CapybaraScreenshotDiff::WindowSizeMismatchError] If the window size doesn't match expectations.
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

    # Alias for backward compatibility with older test suites.
    # @see #screenshot
    alias_method :assert_matches_screenshot, :screenshot

    private

    # Builds a screenshot assertion object that can be validated immediately or later.
    #
    # This method constructs a screenshot assertion that encapsulates the comparison logic.
    # The actual comparison is deferred until {ScreenshotAssertion#validate!} is called.
    #
    # @param name [String] The full name of the screenshot, including any section/group context.
    # @param options [Hash] Options for screenshot taking and comparison.
    #   See {#screenshot} for available options.
    # @param skip_stack_frames [Integer] Number of stack frames to skip for error reporting.
    # @return [ScreenshotAssertion, nil] The assertion object or nil if no assertion is needed.
    # @see ScreenshotAssertion
    def build_screenshot_assertion(name, options, skip_stack_frames: 0)
      Capybara::Screenshot::Diff::ScreenshotMatcher
        .new(name, options)
        .build_screenshot_assertion(skip_stack_frames: skip_stack_frames + 1)
    end
  end
end
