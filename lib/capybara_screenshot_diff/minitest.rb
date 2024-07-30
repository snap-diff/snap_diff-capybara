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

      def screenshot(*, **)
        super
      rescue CapybaraScreenshotDiff::ExpectationNotMet => e
        raise ::Minitest::Assertion, e.message
      end

      alias_method :assert_matches_screenshot, :screenshot

      def self.included(klass)
        klass.setup do
          if ::Capybara::Screenshot.window_size
            ::Capybara::Screenshot::BrowserHelpers.resize_to(::Capybara::Screenshot.window_size)
          end
        end

        klass.teardown do
          errors = verify_screenshots!(@test_screenshots)

          failures << ::Minitest::Assertion.new(errors.join("\n\n")) if errors && !errors.empty?
        end
      end
    end
  end
end
