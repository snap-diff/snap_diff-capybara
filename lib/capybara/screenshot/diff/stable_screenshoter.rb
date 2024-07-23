# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      class StableScreenshoter
        STABILITY_OPTIONS = [:stability_time_limit, :wait]

        attr_reader :stability_time_limit, :wait

        # Initializes a new instance of StableScreenshoter
        #
        # This method sets up a new screenshoter with specific capture and comparison options. It validates the presence of
        # `:stability_time_limit` and `:wait` in capture options and ensures that `:stability_time_limit` is less than or equal to `:wait`.
        #
        # @param capture_options [Hash] The options for capturing screenshots, must include `:stability_time_limit` and `:wait`.
        # @param comparison_options [Hash, nil] The options for comparing screenshots, defaults to `nil` which uses `Diff.default_options`.
        # @raise [ArgumentError] If `:wait` or `:stability_time_limit` are not provided, or if `:stability_time_limit` is greater than `:wait`.
        def initialize(capture_options, comparison_options = nil)
          @stability_time_limit, @wait = capture_options.fetch_values(:stability_time_limit, :wait)

          raise ArgumentError, "wait should be provided for stable screenshots" unless wait
          raise ArgumentError, "stability_time_limit should be provided for stable screenshots" unless stability_time_limit
          raise ArgumentError, "stability_time_limit (#{stability_time_limit}) should be less or equal than wait (#{wait}) for stable screenshots" unless stability_time_limit <= wait

          @comparison_options = comparison_options || Diff.default_options

          driver = Diff::Drivers.for(@comparison_options)
          @screenshoter = Diff.screenshoter.new(capture_options.except(*STABILITY_OPTIONS), driver)
        end

        # Takes a comparison screenshot ensuring page stability
        #
        # Attempts to take a stable screenshot of the page by comparing several screenshot attempts until the page stops updating
        # or the `:wait` limit is reached. If unable to achieve a stable state within the time limit, it annotates the attempts
        # to aid debugging.
        #
        # @param screenshot_path [String, Pathname] The path where the screenshot will be saved.
        # @return [void]
        # @raise [RuntimeError] If a stable screenshot cannot be obtained within the specified `:wait` time.
        def take_comparison_screenshot(screenshot_path)
          new_screenshot_path = take_stable_screenshot(screenshot_path)

          # We failed to get stable browser state! Generate difference between attempts to overview moving parts!
          unless new_screenshot_path
            # FIXME(uwe): Change to store the failure and only report if the test succeeds functionally.
            annotate_attempts_and_fail!(screenshot_path)
          end

          FileUtils.mv(new_screenshot_path, screenshot_path, force: true)
          Screenshoter.cleanup_attempts_screenshots(screenshot_path)
        end

        def take_stable_screenshot(screenshot_path)
          screenshot_path = screenshot_path.is_a?(String) ? Pathname.new(screenshot_path) : screenshot_path
          # We try to compare first attempt with checkout version, in order to not run next screenshots
          attempt_path = nil
          deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait

          # Cleanup all previous attempts for sure
          Screenshoter.cleanup_attempts_screenshots(screenshot_path)

          0.step do |i|
            # FIXME: it should be wait, and wait should be replaced with stability_time_limit
            sleep(stability_time_limit) unless i == 0
            attempt_path, prev_attempt_path = attempt_next_screenshot(attempt_path, i, screenshot_path)
            return attempt_path if attempt_successful?(attempt_path, prev_attempt_path)
            return nil if timeout?(deadline_at)
          end
        end

        private

        def attempt_successful?(attempt_path, prev_attempt_path)
          return false unless prev_attempt_path
          build_comparison_for(attempt_path, prev_attempt_path).quick_equal?
        rescue ArgumentError
          false
        end

        def attempt_next_screenshot(prev_attempt_path, i, screenshot_path)
          new_attempt_path = Screenshoter.gen_next_attempt_path(screenshot_path, i)
          @screenshoter.take_screenshot(new_attempt_path)
          [new_attempt_path, prev_attempt_path]
        end

        def timeout?(deadline_at)
          Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline_at
        end

        def build_comparison_for(attempt_path, previous_attempt_path)
          ImageCompare.new(attempt_path, previous_attempt_path, @comparison_options)
        end

        # TODO: Move to the HistoricalReporter
        def annotate_attempts_and_fail!(screenshot_path)
          screenshot_attempts = Screenshoter.attempts_screenshot_paths(screenshot_path)

          annotate_stabilization_images(screenshot_attempts)

          # TODO: Move fail to the queue after tests passed
          fail("Could not get stable screenshot within #{wait}s:\n#{screenshot_attempts.join("\n")}")
        end

        # TODO: Add tests that we annotate all files except first one
        def annotate_stabilization_images(attempts_screenshot_paths)
          previous_file = nil
          attempts_screenshot_paths.reverse_each do |file_name|
            if previous_file && File.exist?(previous_file)
              attempts_comparison = build_comparison_for(file_name, previous_file)

              if attempts_comparison.different?
                FileUtils.mv(attempts_comparison.reporter.annotated_base_image_path, previous_file, force: true)
              else
                warn "[capybara-screenshot-diff] Some attempts was stable, but mistakenly marked as not: " \
                       "#{previous_file} and #{file_name} are equal"
              end

              FileUtils.rm(attempts_comparison.reporter.annotated_image_path, force: true)
            end

            previous_file = file_name
          end
        end
      end
    end
  end
end
