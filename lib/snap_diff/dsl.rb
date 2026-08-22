# frozen_string_literal: true

# No require of "capybara_screenshot_diff" here: every Capybara::Screenshot
# reference below is inside a method body, resolved lazily at call time, not
# at this file's own load time -- so this unit has no eager dependency on
# the umbrella entry point, and requiring it here would create a require
# cycle back to capybara_screenshot_diff.rb (which requires this file's
# old-path forwarder).
# DSL includes Capybara::DSL directly below, so it needs the base gem
# loaded regardless of what pulled this file in.
require "capybara/dsl"
require "capybara/screenshot/diff/config_legacy"
require "capybara/screenshot/diff/drivers"
require "snap_diff/comparison"
require "capybara/screenshot/diff/screenshot_matcher"
require_relative "screenshot_namer"
require_relative "screenshot_assertion"

module SnapDiff
  # DSL for taking screenshots and making assertions in Capybara tests.
  # This module provides methods for taking screenshots, comparing them against baselines,
  # and managing the comparison process with various configuration options.
  #
  # The DSL is designed to be included in your test context (e.g., RSpec, Minitest)
  # to provide screenshot comparison capabilities.
  module DSL
    include Capybara::DSL

    def screenshot_section(name)
      screenshot_namer.section = name
    end

    def screenshot_group(name)
      screenshot_namer.group = name
    end

    # Takes a screenshot and compares it against a baseline image.
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
    # @option options [Array<Integer>] :crop [left, top, right, bottom] Edge coordinates to crop the screenshot to.
    # @option options [Array<Array<Integer>>] :skip_area Array of [left, top, right, bottom] edge coordinates to ignore.
    # @option options [Numeric] :tolerance (0.001 for :vips driver) Color tolerance for comparison.
    #   Represents the maximum allowed ratio of different pixels (0.0-1.0 scale).
    # @option options [Numeric] :color_distance_limit Maximum allowed color distance between pixels.
    #   Uses Euclidean RGBA distance (0-510 scale). Mutually exclusive with :perceptual_threshold.
    # @option options [Numeric] :perceptual_threshold Maximum perceptual color difference (CIE dE00).
    #   Uses human perception-based scale (0-100+). VIPS only. Takes priority over :color_distance_limit if both set.
    # @option options [Numeric] :shift_distance_limit Maximum allowed shift distance for pixels.
    # @option options [Numeric] :area_size_limit Maximum allowed difference area size in pixels.
    # @option options [Symbol] :driver (:auto) The image processing driver to use (:auto, :chunky_png, :vips).
    # @return [Boolean] True if the screenshot was successfully captured and processed.
    # @raise [SnapDiff::ExpectationNotMet] If comparison fails and immediate validation is enabled.
    # @raise [SnapDiff::UnstableImage] If the image comparison is unstable.
    # @raise [SnapDiff::WindowSizeMismatchError] If the window size doesn't match expectations.
    def assert_matches_screenshot(name, skip_stack_frames: 0, **options)
      return false unless Capybara::Screenshot.active?

      # Get the full name with section and group information
      full_name = SnapDiff.session.screenshot_namer.full_name(name)

      # Build the screenshot assertion
      assertion = build_screenshot_assertion(full_name, options, skip_stack_frames: skip_stack_frames + 1)

      return false unless assertion

      # Determine if validation should be delayed or immediate
      delayed = options.fetch(:delayed, Capybara::Screenshot::Diff.delayed)

      if delayed
        SnapDiff.session.add_assertion(assertion)
      else
        assertion.validate!
      end

      true
    end

    # Convenience wrapper around {#assert_matches_screenshot} and {#capture_screenshot}.
    # @param compare [Boolean] When false, only captures the screenshot without comparing it to a baseline.
    # @see #assert_matches_screenshot
    # @see #capture_screenshot
    def screenshot(name, skip_stack_frames: 0, compare: true, **options)
      if compare
        assert_matches_screenshot(name, skip_stack_frames: skip_stack_frames + 1, **options)
      else
        capture_screenshot(name, **options)
      end
    end

    # Captures a screenshot without comparing it to a baseline.
    # @param name [String] The base name of the screenshot, used to generate the filename.
    # @param options [Hash] Additional options for taking the screenshot. See {#assert_matches_screenshot}.
    # @return [Boolean] True if the screenshot was successfully captured.
    def capture_screenshot(name, **options)
      return false unless Capybara::Screenshot.active?

      full_name = SnapDiff.session.screenshot_namer.full_name(name)
      SnapDiff::ScreenshotMatcher.new(full_name, options).capture

      true
    end

    # Asserts the current page has no visual changes from the baseline.
    # Override in your base test class to add project-specific behavior
    # (e.g., waiting for Turbo, default skip areas).
    def assert_no_screenshot_changes(name, skip_stack_frames: 0, **opts)
      assert_matches_screenshot(name, skip_stack_frames: skip_stack_frames + 1, **opts)
    end

    private

    # Builds a screenshot assertion object that can be validated immediately or later.
    #
    # This method constructs a screenshot assertion that encapsulates the comparison logic.
    # The actual comparison is deferred until {ScreenshotAssertion#validate!} is called.
    #
    # @param name [String] The full name of the screenshot, including any section/group context.
    # @param options [Hash] Options for screenshot taking and comparison.
    #   See {#assert_matches_screenshot} for available options.
    # @param skip_stack_frames [Integer] Number of stack frames to skip for error reporting.
    # @return [ScreenshotAssertion, nil] The assertion object or nil if no assertion is needed.
    # @see ScreenshotAssertion
    def build_screenshot_assertion(name, options, skip_stack_frames: 0)
      SnapDiff::ScreenshotMatcher
        .new(name, options)
        .build_screenshot_assertion(skip_stack_frames: skip_stack_frames + 1)
    end

    def screenshot_namer
      SnapDiff.session.screenshot_namer
    end
  end
end
