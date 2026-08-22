# frozen_string_literal: true

require "capybara_screenshot_diff/snap_manager"
require_relative "screenshoter"
require_relative "stable_screenshoter"
require_relative "browser_helpers"
require_relative "vcs"
require_relative "area_calculator"

module SnapDiff
  class ScreenshotMatcher
    attr_reader :screenshot_full_name, :driver_options, :screenshot_format

    def initialize(screenshot_full_name, options = {})
      @screenshot_full_name = screenshot_full_name
      @driver_options = Capybara::Screenshot::Diff.default_options.merge(options)

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
      unless need_to_compare?
        CapybaraScreenshotDiff.record_new_screenshot(screenshot_full_name)
        return
      end

      create_screenshot_assertion(skip_stack_frames + 1, comparison_options)
    end

    # Captures a screenshot without comparing it to a baseline.
    def capture
      check_window_size!
      prepare_screenshot_options

      capture_options, comparison_options = extract_capture_and_comparison_options!(driver_options)

      @snapshot.manager.create_output_directory_for(@snapshot.path)
      capture_screenshot(capture_options, comparison_options)
    end

    private

    def need_to_compare?
      @snapshot.base_path.exist?
    end

    def check_window_size!
      if BrowserHelpers.window_size_is_wrong?(Capybara::Screenshot.window_size)
        current_size = BrowserHelpers.selenium? ?
          BrowserHelpers.session.driver.browser.manage.window.size.to_s :
          "unknown"

        raise CapybaraScreenshotDiff::WindowSizeMismatchError.new(<<~ERROR.chomp, caller)
          Window size mismatch detected!
          Expected: #{Capybara::Screenshot.window_size.inspect}
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
      driver_options[:driver] = Capybara::Screenshot::Diff::Drivers.for(driver_options[:driver])
    end

    def check_base_screenshot
      @snapshot.checkout_base_screenshot

      if Capybara::Screenshot::Diff.fail_if_new && !@snapshot.base_path.exist?
        raise CapybaraScreenshotDiff::ExpectationNotMet.new(<<~ERROR.chomp, caller)
          No existing screenshot found for #{@snapshot.base_path}!
          To record baselines: RECORD_SCREENSHOTS=1 bundle exec rake test
          To allow new screenshots: Capybara::Screenshot::Diff.fail_if_new = false
        ERROR
      end
    end

    def capture_screenshot(capture_options, comparison_options)
      screenshoter = if capture_options[:stability_time_limit]
        StableScreenshoter.new(capture_options, comparison_options)
      else
        Capybara::Screenshot::Diff.screenshoter.new(capture_options, comparison_options)
      end
      screenshoter.take_comparison_screenshot(@snapshot)
    end

    def create_screenshot_assertion(skip_stack_frames, comparison_options)
      assertion = CapybaraScreenshotDiff::ScreenshotAssertion.new(screenshot_full_name)
      assertion.caller = caller(skip_stack_frames + 1)
      assertion.compare = Capybara::Screenshot::Diff::ImageCompare.new(@snapshot.path, @snapshot.base_path, comparison_options)
      assertion
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
