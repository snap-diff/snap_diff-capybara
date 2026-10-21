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

      # Pre-computation: No need to compare without base screenshot
      return register_uncompared_screenshot unless need_to_compare?

      register(create_screenshot_assertion(skip_stack_frames + 1, comparison_options))
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

    # `:all` accepts every differing rendering as the new baseline -- that is
    # the feature. A mode written in code (a config line, a per-screenshot
    # option) applies to every run, so left on CI it buys a build that never
    # fails, forever. That is precisely how Percy goes green on a job that
    # lost its token; refuse it rather than shipping our own version.
    #
    # The per-run variable is the operator asking for this run to record, so
    # a deliberate recording job (docs/ci-integration.md) gets through. With
    # it set, the whole run is `:all` already; where the mode was written no
    # longer matters, so the guard looks only at the variable.
    #
    # A CI job that must record only NEW baselines does not need `:all`:
    # `record: :once` records them and still fails on everything that differs.
    def refuse_bulk_record_under_ci!
      return unless SnapDiff::Config.ci?
      return if SnapDiff::Config.accept_screenshots?

      raise SnapDiff::ExpectationNotMet.new(<<~ERROR.chomp, caller)
        `record: :all` re-records every screenshot that differs from its baseline without failing, and it was set in code, so it refuses to run under CI (ENV["CI"] is set).
        Left in committed config, no difference could fail this build, ever.
        To record on CI for one run: SNAP_DIFF_ACCEPT_SCREENSHOTS=1
        To record only the screenshots that have no baseline yet: SnapDiff.config.record = :once
      ERROR
    end

    def need_to_compare?
      @snapshot.base_path.exist?
    end

    # The matcher is the one registrar: every assertion it builds is
    # registered here, before any raise, so the end-of-run tally and the
    # reporters see it however the DSL goes on to validate it.
    def register(assertion)
      SnapDiff.session.add_assertion(assertion)
    end

    # No baseline to compare against: the capture is registered as a `:new`
    # assertion with no comparison, in every mode.
    #
    # Runs after a successful capture, so the file handed to reporters is
    # really there, and the path the `:none` message tells the user to
    # `git add` exists by the time they read it (#260). A new one is
    # registered through the session's check, which raises when the baseline
    # was committed but disappeared (#217): that one is not new. The tally is
    # not done here: Reporting counts every registered assertion at reset.
    def register_uncompared_screenshot
      first_sighting = !SnapDiff.session.new_screenshots.include?(screenshot_full_name)
      assertion = SnapDiff.session.record_new_screenshot(screenshot_full_name, path: @snapshot.path)
      fail_if_new_screenshot
      warn_no_committed_baseline if first_sighting
      assertion
    end

    def prepare_screenshot_options
      area_calculator = AreaCalculator.new(driver_options.delete(:crop), driver_options[:skip_area])

      driver_options[:crop] = area_calculator.calculate_crop
      driver_options[:skip_area] = area_calculator.calculate_skip_area
      driver_options[:driver] = SnapDiff::Drivers.for(driver_options[:driver])
    end

    # The git checkout that drives #need_to_compare?, plus the one fact the
    # no-baseline warning needs from before the capture: whether the user
    # had a PNG sitting there already -- the case that confuses people most.
    def check_base_screenshot
      @snapshot.checkout_base_screenshot
      @file_already_there = @snapshot.path.exist?
    end

    # The `:none` raise: immediate whatever `delayed` says, and after the
    # capture, so `git add` on the path it names is a command the user can
    # run on this very test run (#260). The screenshot is registered by then.
    def fail_if_new_screenshot
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
    # once per screenshot, and name what to do about it. Not under
    # `record: :none`: fail_if_new_screenshot raises the same thing with the
    # fix attached.
    def warn_no_committed_baseline
      already_there = @file_already_there ? " (the file already there is not a baseline until it is committed)" : ""
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
      assertion = SnapDiff::ScreenshotAssertion.new(screenshot_full_name, record_mode: record_mode)
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
