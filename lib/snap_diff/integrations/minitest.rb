# frozen_string_literal: true

require "minitest"
require_relative "../dsl"
# SnapDiff.session/.reset/.pending_screenshots_message live in
# snap_diff/screenshot_assertion, SnapDiff::Reporting.finalize! in
# snap_diff/reporting -- neither is pulled in by requiring dsl.rb alone.
require "snap_diff/screenshot_assertion"
require "snap_diff/reporting"

# Only the v1 NAMESPACE entry is a deprecated choice: requiring
# "capybara/screenshot/diff" is a line in the user's own file, and changing
# it is the fix. The gem-NAME file (lib/capybara-screenshot-diff.rb) is not:
# `Bundler.require` requires the gem's own name, so it loads for everyone
# with the gem in their Gemfile whatever they require explicitly -- keying
# the warning off it shouted at every user on every run, with no action
# available to silence it. See test/legacy/minitest_activation_warning_test.rb.
#
# Silenceable through the documented switch (SnapDiff.silence_deprecations /
# SNAP_DIFF_SILENCE_DEPRECATIONS): it was a bare Kernel#warn, so the one knob
# the docs offer did not reach it.
if !SnapDiff.silence_deprecations? && caller.any? { |path| path.include?("capybara/screenshot/diff.rb") }
  warn <<~MSG
    [DEPRECATION] `require "capybara/screenshot/diff"` activates the Minitest assertions for you; that will be removed.
                  Please `require "snap_diff/integrations/minitest"` explicitly.
  MSG
end

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
