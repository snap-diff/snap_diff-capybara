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
        def initialize(*)
          super
          @screenshot_counter = nil
          @screenshot_group = nil
          @screenshot_section = nil
          @test_screenshot_errors = nil
          @test_screenshots = []
        end

        def verify_screenshots!(screenshots = @test_screenshots)
          return unless ::Capybara::Screenshot.active? && ::Capybara::Screenshot::Diff.fail_on_difference

          test_screenshot_errors = screenshots.map do |caller, name, compare|
            assert_image_not_changed(caller, name, compare)
          end

          test_screenshot_errors.compact!

          test_screenshot_errors.presence
        ensure
          screenshots.clear
        end

        def build_full_name(name)
          if @screenshot_counter
            name = format("%02i_#{name}", @screenshot_counter)
            @screenshot_counter += 1
          end

          File.join(*group_parts.push(name.to_s))
        end

        def screenshot_dir
          File.join(*([Screenshot.screenshot_area] + group_parts))
        end

        def screenshot_section(name)
          @screenshot_section = name.to_s
        end

        def screenshot_group(name)
          @screenshot_group = name.to_s
          @screenshot_counter = @screenshot_group.present? ? 0 : nil
          return unless Screenshot.active? && name.present?

          FileUtils.rm_rf screenshot_dir
        end

        def schedule_match_job(job)
          (@test_screenshots ||= []) << job
          true
        end

        def group_parts
          parts = []
          parts << @screenshot_section if @screenshot_section.present?
          parts << @screenshot_group if @screenshot_group.present?
          parts
        end

        # Takes a screenshot and optionally compares it against a baseline image.
        #
        # === Parameters:
        # +name+:: +String+ - The name of the screenshot. This is used to generate the filename.
        # +skip_stack_frames+:: +Integer+ (default: 0) - The number of stack frames to skip when reporting errors. Useful for cleaner error messages.
        # +options+:: +Hash+ - Additional options for taking the screenshot. Can include custom dimensions, selectors for specific elements, etc.
        #
        # === Returns:
        # +Boolean+ - Returns +true+ if the screenshot was successfully captured and matches the baseline (if comparison is enabled). Returns +false+ if screenshot capturing is disabled or if the screenshot does not match the baseline.
        #
        # === Raises:
        # CapybaraScreenshotDiff::ExpectationNotMet - If the screenshot does not match the baseline image and fail_if_new is set to +true+.
        #
        # === Example:
        #   screenshot('login_page', skip_stack_frames: 1, full: true)
        #
        def screenshot(name, skip_stack_frames: 0, **options)
          return false unless Screenshot.active?

          screenshot_full_name = build_full_name(name)
          job = build_screenshot_matches_job(screenshot_full_name, options)

          unless job
            if Screenshot::Diff.fail_if_new
              raise_error(<<-ERROR.strip_heredoc, caller(2))
                No existing screenshot found for #{screenshot_full_name}!
                To stop seeing this error disable by `Capybara::Screenshot::Diff.fail_if_new=false`
              ERROR
            end

            return false
          end

          job.prepend(caller(skip_stack_frames))

          if Screenshot::Diff.delayed
            schedule_match_job(job)
          else
            error_msg = assert_image_not_changed(*job)
            raise_error(error_msg, caller(2)) if error_msg
          end
        end

        def assert_image_not_changed(caller, name, comparison)
          result = comparison.different?

          # Cleanup after comparisons
          if !result && comparison.base_image_path.exist?
            FileUtils.mv(comparison.base_image_path, comparison.image_path, force: true)
          else
            FileUtils.rm_rf(comparison.base_image_path)
          end

          return unless result

          "Screenshot does not match for '#{name}' #{comparison.error_message}\n#{caller}"
        end

        private

        def raise_error(error_msg, backtrace)
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
