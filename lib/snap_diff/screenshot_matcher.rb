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
    attr_reader :screenshot_full_name, :driver_options, :screenshot_format, :record_mode

    def initialize(screenshot_full_name, options = {})
      @screenshot_full_name = screenshot_full_name
      # BEFORE the merge below -- see SnapDiff.compare. Afterwards `:driver`
      # is present for every caller and proves nothing.
      Removal.warn_once(:driver_setting, Removal::DRIVER_REMOVED) if options.key?(:driver)
      @driver_options = SnapDiff.config.default_options.merge(options)

      # `record:` is a workflow mode, not a capture or comparison option, so
      # it is carved out here rather than added to Comparison::KNOWN_OPTIONS
      # -- a key that hash accepts and nothing downstream reads is the
      # silent no-op ADR-010 forbids. Deleted before anything else touches
      # the hash, so no later split has to know about it.
      @record_mode = resolve_record_mode(@driver_options.delete(:record))

      @screenshot_format = @driver_options[:screenshot_format]
      @snapshot = SnapDiff::SnapManager.snapshot(screenshot_full_name, @screenshot_format)
    end

    def build_screenshot_assertion(skip_stack_frames: 0)
      # Here rather than in #initialize, so it covers exactly the path where
      # `:all` means anything. #capture never compares against a baseline, so
      # the mode has nothing to say about it and refusing there would be a
      # failure invented out of a setting that changes nothing.
      refuse_bulk_record_under_ci! if record_mode == :all

      Capture::Viewport.prepare!(SnapDiff.config.window_size)
      prepare_screenshot_options
      check_base_screenshot

      capture_options, comparison_options = extract_capture_and_comparison_options(driver_options)

      capture_screenshot(capture_options, comparison_options)

      # AFTER the capture, so the path the message tells the user to
      # `git add` is one that exists by the time they read it (#260).
      fail_if_new_screenshot

      # Pre-computation: No need to compare without base screenshot
      # NOTE: Consider to return PreValid Assertion Value Object with hard coded valid result
      unless need_to_compare?
        record_uncompared_screenshot
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

    # The per-screenshot option outranks the configured mode, which in turn
    # outranks `fail_if_new` (SnapDiff::Config#record). One resolution, so
    # both routes to a mode agree about everything downstream.
    def resolve_record_mode(per_screenshot)
      SnapDiff::Config.validate_record_mode!(per_screenshot) || SnapDiff.config.record
    end

    # `:all` accepts every rendering as correct -- that is the feature. On
    # CI there is nobody to review the result and the re-recorded files go
    # away with the box, so a mode left in a committed config file buys a
    # build that compares nothing and passes, forever. That is precisely how
    # Percy goes green on a job that lost its token; refuse it rather than
    # shipping our own version.
    #
    # A CI job that must record NEW baselines does not need `:all` at all:
    # `record: :once` records them and still compares everything that has a
    # baseline (docs/ci-integration.md).
    def refuse_bulk_record_under_ci!
      return if ENV["CI"].to_s.empty?

      raise SnapDiff::ExpectationNotMet.new(<<~ERROR.chomp, caller)
        `record: :all` re-records every baseline WITHOUT comparing, so it refuses to run under CI (ENV["CI"] is set).
        Nothing would be verified and the recorded screenshots would be discarded with the runner.
        Re-record locally, review the result, and commit the screenshots.
        To let a CI job record screenshots that have no baseline yet: SnapDiff.config.record = :once
      ERROR
    end

    # No `record_mode != :all` clause here on purpose: mutation testing
    # showed one guards nothing. #check_base_screenshot already leaves `:all`
    # with no base file at all, so this reads false for it either way, and a
    # second condition that cannot fire is a second thing to keep true.
    def need_to_compare?
      @snapshot.base_path.exist?
    end

    # `:all` re-records, so nothing was compared and nothing is "new" in the
    # missing-baseline sense. Reported through its own channel, which counts
    # only the screenshots that really went down this path.
    def record_uncompared_screenshot
      if record_mode == :all
        SnapDiff::Reporting.record_rerecorded_baseline(screenshot_full_name)
      else
        SnapDiff.session.record_new_screenshot(screenshot_full_name)
      end
    end

    def prepare_screenshot_options
      area_calculator = AreaCalculator.new(driver_options.delete(:crop), driver_options[:skip_area])

      driver_options[:crop] = area_calculator.calculate_crop
      driver_options[:skip_area] = area_calculator.calculate_skip_area
      driver_options[:driver] = SnapDiff::Drivers.for(driver_options[:driver])
    end

    # The git checkout that drives #need_to_compare?, plus the half of the
    # no-baseline reporting that MUST run before the capture: it is the only
    # moment at which `@snapshot.path` still tells us whether the user had a
    # PNG sitting there already -- the case that confuses people most.
    def check_base_screenshot
      # `:all` does not ask git for a baseline -- there is nothing to
      # compare against. A `.base.<fmt>` left by an earlier failing run
      # would otherwise sit beside the re-recorded screenshot and land in
      # the user's `git add`.
      return discard_base_screenshot if record_mode == :all

      @snapshot.checkout_base_screenshot
      return if @snapshot.base_path.exist?
      # fail_if_new_screenshot raises after the capture and says the same
      # thing with the fix attached; two messages for one missing baseline
      # is one too many.
      return if record_mode == :none

      warn_no_committed_baseline
    end

    def discard_base_screenshot
      @snapshot.base_path.delete if @snapshot.base_path.exist?
    end

    # Runs AFTER the capture, so `@snapshot.path` names a file that is
    # really there and `git add` on it is a command the user can run on this
    # very test run (#260). Before, the raise came first and the screenshot
    # was never written -- the instruction was unfollowable in CI, the one
    # place fail_if_new is on by default.
    def fail_if_new_screenshot
      return if @snapshot.base_path.exist?
      return unless record_mode == :none

      raise SnapDiff::ExpectationNotMet.new(<<~ERROR.chomp, caller)
        No existing screenshot found for #{@snapshot.path}!
        To record it: `git add #{@snapshot.path}` and commit -- baselines are read from git.
        To allow new screenshots: SnapDiff.config.record = :once (was: SnapDiff.config.fail_if_new = false)
      ERROR
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
