# frozen_string_literal: true

require "capybara_screenshot_diff"

module CapybaraScreenshotDiff
  module NonMinitest
    module Assertions
      def self.included(klass)
        klass.include ::Capybara::Screenshot::Diff::TestMethods

        klass.setup do
          if ::Capybara::Screenshot.active? && ::Capybara::Screenshot.window_size
            ::Capybara::Screenshot::BrowserHelpers.resize_to(::Capybara::Screenshot.window_size)
          end
        end

        klass.teardown do
          if ::Capybara::Screenshot.active? && ::Capybara::Screenshot::Diff.fail_on_difference
            errors = verify_screenshots!(@test_screenshots)
            raise ::StandardError.new(errors.join("\n\n")) if errors
          end
        end
      end
    end
  end
end
