# frozen_string_literal: true

require "minitest"
require_relative "../dsl"
# The CapybaraScreenshotDiff.verify/.reset/.pending_screenshots_message/
# .finalize_reporters! calls below need the registry singleton machinery,
# which lives in the *old* capybara_screenshot_diff/screenshot_assertion.rb
# file (deliberately not moved -- see that file's own comment) and is no
# longer pulled in transitively by requiring dsl.rb alone.
require "capybara_screenshot_diff/screenshot_assertion"

used_deprecated_entrypoint = caller.any? do |path|
  path.include?("capybara-screenshot-diff.rb") || path.include?("capybara/screenshot/diff.rb")
end

if used_deprecated_entrypoint
  warn <<~MSG
    [DEPRECATION] The default activation of `capybara_screenshot_diff/minitest` will be removed.
                  Please `require "capybara_screenshot_diff/minitest"` explicitly.
  MSG
end

module SnapDiff
  module Minitest
    module Assertions
      include ::SnapDiff::DSL

      def assert_matches_screenshot(*args, skip_stack_frames: 0, **opts)
        self.assertions += 1

        super(*args, skip_stack_frames: skip_stack_frames + 1, **opts)
      rescue ::CapybaraScreenshotDiff::ExpectationNotMet => e
        raise ::Minitest::Assertion, e.message
      end

      def setup
        super
        ::SnapDiff::BrowserHelpers.resize_window_if_needed
      end

      def before_teardown
        super
        CapybaraScreenshotDiff.verify

        # Computed here (before teardown/reset), but the actual `skip` is
        # deferred to `after_teardown` so a real error raised by the user's
        # `teardown` isn't masked by a pending skip recorded before it ran.
        @capybara_screenshot_diff_pending_message = CapybaraScreenshotDiff.pending_screenshots_message
      rescue CapybaraScreenshotDiff::ExpectationNotMet => e
        assertion = ::Minitest::Assertion.new(e)
        assertion.set_backtrace(e.backtrace)
        failures << assertion
      ensure
        CapybaraScreenshotDiff.reset
      end

      def after_teardown
        super

        # Never mask a real failure (from `verify` above or from the user's
        # own `teardown`) with a pending marker.
        if failures.empty? && (msg = @capybara_screenshot_diff_pending_message)
          skip(msg)
        end
      end
    end
  end
end

::Minitest.after_run { CapybaraScreenshotDiff.finalize_reporters! } if ::Minitest.respond_to?(:after_run)
