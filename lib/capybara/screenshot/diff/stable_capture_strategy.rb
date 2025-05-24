# frozen_string_literal: true

require_relative "capture_strategy"
require_relative "stable_screenshoter"

module Capybara
  module Screenshot
    module Diff
      # Capture strategy that waits until the page content stabilises by taking
      # several attempts and comparing them.
      class StableCaptureStrategy < CaptureStrategy
        def initialize(capture_options, comparison_options)
          super
          @screenshoter = StableScreenshoter.new(capture_options, comparison_options)
        end

        def take_comparison_screenshot(snapshot)
          @screenshoter.take_comparison_screenshot(snapshot)
        end
      end
    end
  end
end
