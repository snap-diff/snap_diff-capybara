# frozen_string_literal: true

require "snap_diff/screenshot_assertion"
require "snap_diff/reporting"
# ScreenshotAssertion / AssertionRegistry forward lazily (with deprecation
# warnings) via snap_diff/legacy_shims' const_missing since v2 step 6.
require "snap_diff/legacy_shims"

# CapybaraScreenshotDiff's module methods cover two lifecycles with
# different scopes, kept separate below:
#
# - Session lifecycle: thread-local, per-test. The AssertionRegistry holds
#   the assertions and screenshot names of the test running on this thread;
#   `reset` clears it between tests.
# - Reporter lifecycle: process-global, suite-long. Owned by
#   SnapDiff::Reporting; the methods here are thin public shims over it.
#
# `reset` is the one deliberate bridge between the two: a finished test's
# assertions are handed to the reporters before the registry is cleared.
module CapybaraScreenshotDiff
  class << self
    require "forwardable"
    extend Forwardable

    # --- Session lifecycle (thread-local, per-test) ---

    def registry
      Thread.current[:capybara_screenshot_diff_registry] ||= SnapDiff::AssertionRegistry.new
    end

    def_delegators :registry, :add_assertion, :assertions, :assertions_present?,
      :failed_assertions, :record_new_screenshot, :new_screenshots,
      :new_screenshots_present?, :screenshot_namer, :verify

    def reset
      notify_reporters(registry.assertions)
      registry.reset
    end

    # Message to skip the test with when a new screenshot has no baseline yet
    # and `pending_if_new` is enabled. Adapters call this after verifying
    # screenshots, and skip the test with the returned message when present.
    #
    # @return [String, nil] the pending message, or nil when there is nothing to report
    def pending_screenshots_message
      return unless ::Capybara::Screenshot::Diff.pending_if_new && new_screenshots_present?

      "No baseline for: #{new_screenshots.join(", ")}. Commit the captured screenshots to record them."
    end

    # --- Reporter lifecycle (process-global, suite-long) ---

    def reporters
      SnapDiff::Reporting.reporters
    end

    def reporters_mutex
      SnapDiff::Reporting.mutex
    end

    def finalize_reporters!
      SnapDiff::Reporting.finalize!
    end

    private

    def notify_reporters(assertions)
      SnapDiff::Reporting.notify(assertions)
    end
  end
end
