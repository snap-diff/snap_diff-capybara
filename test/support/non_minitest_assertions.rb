# frozen_string_literal: true

require "capybara_screenshot_diff"

module CapybaraScreenshotDiff
  module NonMinitest
    module Assertions
      def self.included(klass)
        klass.include CapybaraScreenshotDiff::DSL

        klass.setup do
          Capybara::Screenshot::BrowserHelpers.resize_window_if_needed
        end

        klass.teardown do
          CapybaraScreenshotDiff.verify
        ensure
          CapybaraScreenshotDiff.reset
        end
      end
    end
  end
end
