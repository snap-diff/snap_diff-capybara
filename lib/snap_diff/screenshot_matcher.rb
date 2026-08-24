# frozen_string_literal: true

require "snap_diff/removal"
require "snap_diff/snap_manager"
require_relative "screenshoter"
require_relative "stable_screenshoter"
require_relative "browser_helpers"
require_relative "capture/viewport"
require_relative "vcs"
require_relative "area_calculator"
require_relative "reporting"

module SnapDiff
  class ScreenshotMatcher
    attr_reader :screenshot_full_name, :driver_options, :screenshot_format

    def initialize(screenshot_full_name, options = {})
      @screenshot_full_name = screenshot_full_name
      # BEFORE the merge below -- see SnapDiff.compare. Afterwards `:driver`
      # is present for every caller and proves nothing.
      Removal.warn_once(:driver_setting, Removal::DRIVER_REMOVED) if options.key?(:driver)
      @driver_options = SnapDiff.config.default_options.merge(options)

      @screenshot_format = @driver_options[:screenshot_format]
      @snapshot = SnapDiff::SnapManager.snapshot(screenshot_full_name, @screenshot_format)
    end

    def build_screenshot_assertion(skip_stack_frames: 0)
      Capture::Viewport.prepare!(SnapDiff.config.window_size)
      prepare_screenshot_options
      check_base_screenshot

      capture_options, comparison_options = extract_capture_and_comparison_options(driver_options)

      capture_screenshot(capture_options, comparison_options)

      # Pre-computation: No need to compare without base screenshot
      # NOTE: Consider to return PreValid Assertion Value Object with hard coded valid result
      unless need_to_compare?
        SnapDiff.session.record_new_screenshot(screenshot_full_name)
        return
      end

      create_screenshot_assertion(skip_stack_frames + 1, comparison_options)
    end

    # Captures a screenshot without comparing it to a baseline.
    def capture
      Capture::Viewport.prepare!(SnapDiff.config.window_size)
      prepare_screenshot_options

      capture_options, comparison_options = extract_capture_and_comparison_options(driver_options)

      @snapshot.manager.create_output_directory_for(@snapshot.path)
      capture_screenshot(capture_options, comparison_options)
    end

    private

    def need_to_compare?
      @snapshot.base_path.exist?
    end

    def prepare_screenshot_options
      area_calculator = AreaCalculator.new(driver_options.delete(:crop), driver_options[:skip_area])

      driver_options[:crop] = area_calculator.calculate_crop
      driver_options[:skip_area] = area_calculator.calculate_skip_area
      driver_options[:driver] = SnapDiff::Drivers.for(driver_options[:driver])
    end

    def check_base_screenshot
      @snapshot.checkout_base_screenshot
      return if @snapshot.base_path.exist?

      # Runs BEFORE the capture below, which is the only moment at which
      # `@snapshot.path` still tells us whether the user had a PNG sitting
      # there already -- the case that confuses people most.
      if SnapDiff.config.fail_if_new
        raise SnapDiff::ExpectationNotMet.new(<<~ERROR.chomp, caller)
          No existing screenshot found for #{@snapshot.path}!
          To record it: run the test, then `git add #{@snapshot.path}` and commit -- baselines are read from git.
          To allow new screenshots: SnapDiff.config.fail_if_new = false
        ERROR
      end

      warn_no_committed_baseline
    end

    # `fail_if_new` defaults to false off CI, deliberately: a new screenshot
    # must not break a local run. The cost is that nothing is compared and
    # the test passes whatever the page looks like, while the capture
    # overwrites the file on disk -- a green run that proves nothing. Say so
    # once per screenshot, and name what to do about it.
    def warn_no_committed_baseline
      return unless SnapDiff::Reporting.record_missing_baseline(screenshot_full_name)

      already_there = @snapshot.path.exist? ? " (the file already there is not a baseline until it is committed)" : ""
      warn "[snap_diff] No committed baseline for #{@snapshot.path}#{already_there} -- nothing was compared. " \
        "Commit it to enable comparison."
    end

    def capture_screenshot(capture_options, comparison_options)
      screenshoter = if capture_options[:stability_time_limit]
        StableScreenshoter.new(capture_options, comparison_options)
      else
        SnapDiff.config.screenshoter.new(capture_options, comparison_options)
      end
      screenshoter.take_comparison_screenshot(@snapshot)
    end

    def create_screenshot_assertion(skip_stack_frames, comparison_options)
      assertion = SnapDiff::ScreenshotAssertion.new(screenshot_full_name)
      assertion.caller = caller(skip_stack_frames + 1)
      assertion.compare = Comparison.new(@snapshot.path, @snapshot.base_path, comparison_options)
      assertion
    end

    # Pure partition of one options hash into [capture_options,
    # comparison_options]. Unlike the previous delete-based carve, this
    # method itself does not mutate its input hash.
    def extract_capture_and_comparison_options(driver_options = {})
      capture_options = {
        # screenshot options
        capybara_screenshot_options: driver_options[:capybara_screenshot_options],
        crop: driver_options[:crop],
        # delivery options
        screenshot_format: driver_options[:screenshot_format],
        # stability options
        stability_time_limit: driver_options[:stability_time_limit],
        wait: driver_options[:wait]
      }

      [capture_options, driver_options.except(:crop, :stability_time_limit, :wait)]
    end
  end
end
