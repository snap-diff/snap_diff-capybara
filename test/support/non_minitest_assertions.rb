# frozen_string_literal: true

require "capybara_screenshot_diff"

module CapybaraScreenshotDiff
  module NonMinitest
    module Assertions
      def self.included(klass)
        klass.include SnapDiff::DSL

        klass.setup do
          SnapDiff::BrowserHelpers.resize_window_if_needed
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
