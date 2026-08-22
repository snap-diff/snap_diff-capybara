# frozen_string_literal: true

require "snap_diff/screenshot_assertion"
require "snap_diff/reporting"
# ScreenshotAssertion / AssertionRegistry forward lazily (with deprecation
# warnings) via snap_diff/legacy_shims' const_missing since v2 step 6.
require "snap_diff/legacy_shims"

# Since ADR-008 step 6 every method here is a thin forwarder; the canonical
# homes are SnapDiff (session lifecycle: per-test, `SnapDiff.session` and
# friends) and SnapDiff::Reporting (reporter lifecycle: process-global,
# suite-long). Names, arities and object identities are unchanged -- this
# module stays as the compatibility surface for existing consumers.
module CapybaraScreenshotDiff
  class << self
    require "forwardable"
    extend Forwardable

    # --- Session lifecycle (per-test) -> SnapDiff ---

    def registry
      SnapDiff.session
    end

    def_delegators :registry, :add_assertion, :assertions, :assertions_present?,
      :failed_assertions, :record_new_screenshot, :new_screenshots,
      :new_screenshots_present?, :screenshot_namer, :verify

    # Written out rather than def_delegators so the arities stay 0 (a
    # Forwardable-generated method takes *args, **kwargs, &block).
    def reset
      SnapDiff.reset
    end

    def pending_screenshots_message
      SnapDiff.pending_screenshots_message
    end

    # --- Reporter lifecycle (process-global, suite-long) -> SnapDiff::Reporting ---

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
