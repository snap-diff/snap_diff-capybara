# frozen_string_literal: true

require "minitest"
require "capybara_screenshot_diff/dsl"

used_deprecated_entrypoint = caller.any? do |path|
  path.include?("capybara-screenshot-diff.rb") || path.include?("capybara/screenshot/diff.rb")
end

if used_deprecated_entrypoint
  warn <<~MSG
    [DEPRECATION] The default activation of `capybara_screenshot_diff/minitest` will be removed. 
                  Please `require "capybara_screenshot_diff/minitest"` explicitly.
  MSG
end

module CapybaraScreenshotDiff
  module Minitest
    module Assertions
      include ::CapybaraScreenshotDiff::DSL

      def screenshot(*args, skip_stack_frames: 0, **opts)
        self.assertions += 1

        super(*args, skip_stack_frames: skip_stack_frames + 1, **opts)
      rescue ::CapybaraScreenshotDiff::ExpectationNotMet => e
        raise ::Minitest::Assertion, e.message
      end

      alias_method :assert_matches_screenshot, :screenshot

      def setup
        super
        ::Capybara::Screenshot::BrowserHelpers.resize_window_if_needed
      end

      def before_teardown
        super
        CapybaraScreenshotDiff.verify
      rescue CapybaraScreenshotDiff::ExpectationNotMet => e
        assertion = ::Minitest::Assertion.new(e)
        assertion.set_backtrace(e.backtrace)
        failures << assertion
      ensure
        CapybaraScreenshotDiff.reset
      end
    end
  end
end
