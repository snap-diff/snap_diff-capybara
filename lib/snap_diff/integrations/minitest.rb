# frozen_string_literal: true

require "minitest"
require_relative "../dsl"
# SnapDiff.session/.reset/.pending_screenshots_message live in
# snap_diff/screenshot_assertion, SnapDiff::Reporting.finalize! in
# snap_diff/reporting -- neither is pulled in by requiring dsl.rb alone.
require "snap_diff/screenshot_assertion"
require "snap_diff/reporting"

module SnapDiff
  module Minitest
    module Assertions
      include ::SnapDiff::DSL

      def assert_matches_screenshot(*args, skip_stack_frames: 0, **opts)
        self.assertions += 1

        super(*args, skip_stack_frames: skip_stack_frames + 1, **opts)
      rescue ::SnapDiff::ExpectationNotMet => e
        raise ::Minitest::Assertion, e.message
      end

      def setup
        super
        ::SnapDiff::BrowserHelpers.resize_window_if_needed
      end

      def before_teardown
        super
        SnapDiff.session.verify

        # Computed here (before teardown/reset), but the actual `skip` is
        # deferred to `after_teardown` so a real error raised by the user's
        # `teardown` isn't masked by a pending skip recorded before it ran.
        @capybara_screenshot_diff_pending_message = SnapDiff.pending_screenshots_message
      rescue SnapDiff::ExpectationNotMet => e
        assertion = ::Minitest::Assertion.new(e)
        assertion.set_backtrace(e.backtrace)
        failures << assertion
      ensure
        SnapDiff.reset
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

::Minitest.after_run { SnapDiff::Reporting.finalize! } if ::Minitest.respond_to?(:after_run)
