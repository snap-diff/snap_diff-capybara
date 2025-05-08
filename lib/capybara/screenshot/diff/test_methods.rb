# frozen_string_literal: true

require "English"
require "capybara"
require "action_controller"
require "action_dispatch"
require "active_support/core_ext/string/strip"
require "pathname"

require_relative "drivers"
require_relative "image_compare"
require_relative "vcs"
require_relative "browser_helpers"
require_relative "region"

require_relative "screenshot_matcher"

# == Capybara::Screenshot::Diff::TestMethods
#
# This module provides methods for capturing screenshots and verifying them against
# baseline images to detect visual changes. It's designed to be included in test
# classes to add visual regression testing capabilities.

module Capybara
  module Screenshot
    module Diff
      module TestMethods
        # @!attribute [rw] test_screenshots
        #   @return [Array(Array(Array(String), String, ImageCompare | Minitest::Mock))] An array where each element is an array containing the caller context,
        #     the name of the screenshot, and the comparison object. This attribute stores information about each screenshot
        #     scheduled for comparison to ensure they do not show any unintended differences.
        def initialize(*)
          super
          @screenshot_counter = nil
          @screenshot_group = nil
          @screenshot_section = nil
          @test_screenshot_errors = nil
        end

        # Builds the full name for a screenshot, incorporating counters and group names for uniqueness.
        #
        # @param name [String] The base name for the screenshot.
        # @return [String] The full, unique name for the screenshot.
        def build_full_name(name)
          if @screenshot_counter
            name = format("%02i_#{name}", @screenshot_counter)
            @screenshot_counter += 1
          end

          File.join(*group_parts.push(name.to_s))
        end

        # Determines the directory path for saving screenshots.
        #
        # @return [String] The full path to the directory where screenshots are saved.
        def screenshot_dir
          File.join(*([Screenshot.screenshot_area] + group_parts))
        end

        def screenshot_section(name)
          @screenshot_section = name.to_s
        end

        def screenshot_group(name)
          @screenshot_group = name.to_s
          @screenshot_counter = (@screenshot_group.nil? || @screenshot_group.empty?) ? nil : 0
          name_present = !(name.nil? || name.empty?)
          return unless Screenshot.active? && name_present

          FileUtils.rm_rf screenshot_dir
        end

        # Schedules a screenshot comparison job for later execution.
        #
        # This method adds a job to the queue of screenshots to be matched. It's used when `Capybara::Screenshot::Diff.delayed`
        # is set to true, allowing for batch processing of screenshot comparisons at a later point, typically at the end of a test.
        #
        # @param job [Array(Array(String), String, ImageCompare)] The job to be scheduled, consisting of the caller context, screenshot name, and comparison object.
        # @return [Boolean] Always returns true, indicating the job was successfully scheduled.
        def schedule_match_job(job)
          CapybaraScreenshotDiff.add_assertion(job)
          true
        end

        def group_parts
          parts = []
          parts << @screenshot_section unless @screenshot_section.nil? || @screenshot_section.empty?
          parts << @screenshot_group unless @screenshot_group.nil? || @screenshot_group.empty?
          parts
        end

        # Takes a screenshot and optionally compares it against a baseline image.
        #
        # @param name [String] The name of the screenshot, used to generate the filename.
        # @param skip_stack_frames [Integer] The number of stack frames to skip when reporting errors, for cleaner error messages.
        # @param options [Hash] Additional options for taking the screenshot, such as custom dimensions or selectors.
        # @return [Boolean] Returns true if the screenshot was successfully captured and matches the baseline, false otherwise.
        # @raise [CapybaraScreenshotDiff::ExpectationNotMet] If the screenshot does not match the baseline image and fail_if_new is set to true.
        # @example Capture a full-page screenshot named 'login_page'
        #   screenshot('login_page', skip_stack_frames: 1, full: true)
        def screenshot(name, skip_stack_frames: 0, **options)
          return false unless Screenshot.active?

          # setup
          screenshot_full_name = build_full_name(name)

          # exercise
          match_changes_job = build_screenshot_matches_job(screenshot_full_name, options)

          # verify
          backtrace = caller(skip_stack_frames + 1).reject { |l| l =~ /gems\/(activesupport|minitest|railties)/ }

          unless match_changes_job
            if Screenshot::Diff.fail_if_new
              _raise_error(<<-ERROR.strip_heredoc, backtrace)
                No existing screenshot found for #{screenshot_full_name}!
                To stop seeing this error disable by `Capybara::Screenshot::Diff.fail_if_new=false`
              ERROR
            end

            return false
          end

          match_changes_job.prepend(backtrace)

          if Screenshot::Diff.delayed
            schedule_match_job(match_changes_job)
          else
            invoke_match_job(match_changes_job)
          end
        end

        private

        def invoke_match_job(job)
          error_msg = CapybaraScreenshotDiff::ScreenshotAssertion.from(job).validate

          if error_msg
            _raise_error(error_msg, job[0])
          end

          true
        end

        def _raise_error(error_msg, backtrace)
          raise CapybaraScreenshotDiff::ExpectationNotMet.new(error_msg).tap { _1.set_backtrace(backtrace) }
        end

        def build_screenshot_matches_job(screenshot_full_name, options)
          ScreenshotMatcher
            .new(screenshot_full_name, options)
            .build_screenshot_matches_job
        end
      end
    end
  end
end
