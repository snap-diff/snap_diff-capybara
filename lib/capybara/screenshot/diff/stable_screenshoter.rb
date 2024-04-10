# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      class StableScreenshoter
        STABILITY_OPTIONS = [:stability_time_limit, :wait]

        attr_reader :stability_time_limit, :wait

        def initialize(capture_options, comparison_options = nil)
          @stability_time_limit, @wait = capture_options.fetch_values(:stability_time_limit, :wait)
          raise ArgumentError, "wait should be provided" unless @wait
          raise ArgumentError, "stability_time_limit should be provided for stable screenshots" unless @stability_time_limit
          raise ArgumentError, "stability_time_limit should be less than wait for stable screenshots" if @stability_time_limit > @wait

          @comparison_options = comparison_options || Diff.default_options

          driver = Diff::Drivers.for(@comparison_options)
          @screenshoter = Diff.screenshoter.new(capture_options.except(*STABILITY_OPTIONS), driver)
        end

        # Try to get screenshot from browser.
        # On `stability_time_limit` it checks that page stop updating by comparison several screenshot attempts
        # On reaching `wait` limit then it has been failed. On failing we annotate screenshot attempts to help to debug
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
          screenshot_started_at = last_attempt_at = Time.now

          # Cleanup all previous attempts for sure
          Screenshoter.cleanup_attempts_screenshots(screenshot_path)

          0.step do |i|
            # Prevents redundant screenshots generations
            sleep(stability_time_limit) unless i == 0

            elapsed_time = last_attempt_at - screenshot_started_at

            prev_attempt_path = attempt_path
            attempt_path = Screenshoter.gen_next_attempt_path(screenshot_path, i)

            @screenshoter.take_screenshot(attempt_path)
            last_attempt_at = Time.now

            next unless prev_attempt_path
            stabilization_comparator = build_comparison_for(attempt_path, prev_attempt_path)

            # If previous screenshot is equal to the current, then we are good
            return attempt_path if prev_attempt_path && does_not_require_next_attempt?(stabilization_comparator)

            # If timeout then we failed to generate valid screenshot
            return nil if timeout?(elapsed_time)
          end
        end

        private

        def does_not_require_next_attempt?(stabilization_comparator)
          stabilization_comparator.quick_equal?
        rescue ArgumentError
          false
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

        def timeout?(elapsed_time)
          elapsed_time > wait
        end
      end
    end
  end
end
