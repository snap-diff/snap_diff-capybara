# frozen_string_literal: true

require "capybara_screenshot_diff/snap_manager"
require_relative "screenshoter"
require_relative "stable_screenshoter"
require_relative "browser_helpers"
require_relative "vcs"
require_relative "area_calculator"
require_relative "screenshot_coordinator"

module Capybara
  module Screenshot
    module Diff
      class ScreenshotMatcher
        attr_reader :screenshot_full_name, :driver_options, :screenshot_format

        def initialize(screenshot_full_name, options = {})
          @screenshot_full_name = screenshot_full_name
          @driver_options = Diff.default_options.merge(options)

          @screenshot_format = @driver_options[:screenshot_format]
          @snapshot = CapybaraScreenshotDiff::SnapManager.snapshot(screenshot_full_name, @screenshot_format)
        end

        def build_screenshot_assertion(skip_stack_frames: 0)
          check_window_size!
          prepare_screenshot_options
          check_base_screenshot

          capture_options, comparison_options = extract_capture_and_comparison_options!(driver_options)

          capture_screenshot(capture_options, comparison_options)

          # Pre-computation: No need to compare without base screenshot
          # NOTE: Consider to return PreValid Assertion Value Object with hard coded valid result
          return unless need_to_compare?

          create_screenshot_assertion(skip_stack_frames + 1, comparison_options)
        end

        private

        def need_to_compare?
          @snapshot.base_path.exist?
        end

        def check_window_size!
          if BrowserHelpers.window_size_is_wrong?(Screenshot.window_size)
            current_size = BrowserHelpers.selenium? ?
              BrowserHelpers.session.driver.browser.manage.window.size.to_s :
              "unknown"

            raise CapybaraScreenshotDiff::WindowSizeMismatchError.new(<<~ERROR.chomp, caller)
              Window size mismatch detected!
              Expected: #{Screenshot.window_size.inspect}
              Actual: #{current_size}
              
              Screenshots cannot be compared when window sizes don't match.
              Please ensure the browser window is properly sized before taking screenshots.
            ERROR
          end
        end

        def prepare_screenshot_options
          area_calculator = AreaCalculator.new(driver_options.delete(:crop), driver_options[:skip_area])

          driver_options[:crop] = area_calculator.calculate_crop
          driver_options[:skip_area] = area_calculator.calculate_skip_area
          driver_options[:driver] = Drivers.for(driver_options[:driver])
        end

        def check_base_screenshot
          @snapshot.checkout_base_screenshot

          if Capybara::Screenshot::Diff.fail_if_new && !@snapshot.base_path.exist?
            raise CapybaraScreenshotDiff::ExpectationNotMet.new(<<~ERROR.chomp, caller)
              No existing screenshot found for #{@snapshot.base_path}!
              To stop seeing this error disable by `Capybara::Screenshot::Diff.fail_if_new=false`
            ERROR
          end
        end

        def capture_screenshot(capture_options, comparison_options)
          Capybara::Screenshot::Diff::ScreenshotCoordinator.capture(@snapshot, capture_options, comparison_options)
        end

        def create_screenshot_assertion(skip_stack_frames, comparison_options)
          CapybaraScreenshotDiff::ScreenshotAssertion.from([
            caller(skip_stack_frames + 1),
            screenshot_full_name,
            ImageCompare.new(@snapshot.path, @snapshot.base_path, comparison_options)
          ])
        end

        def extract_capture_and_comparison_options!(driver_options = {})
          [
            {
              # screenshot options
              capybara_screenshot_options: driver_options[:capybara_screenshot_options],
              crop: driver_options.delete(:crop),
              # delivery options
              screenshot_format: driver_options[:screenshot_format],
              # stability options
              stability_time_limit: driver_options.delete(:stability_time_limit),
              wait: driver_options.delete(:wait)
            },
            driver_options
          ]
        end
      end
    end
  end
end
