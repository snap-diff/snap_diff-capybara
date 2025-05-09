# frozen_string_literal: true

require_relative "capture_strategy"
require_relative "screenshoter"

module Capybara
  module Screenshot
    module Diff
      # Default capture strategy – grabs a single screenshot via the generic
      # `Screenshoter` and returns immediately.
      class StandardCaptureStrategy < CaptureStrategy
        def initialize(capture_options, comparison_options)
          super
          driver = comparison_options[:driver]
          @screenshoter = Diff.screenshoter.new(capture_options, driver)
        end

        def take_comparison_screenshot(snapshot)
          @screenshoter.take_comparison_screenshot(snapshot)
        end
      end
    end
  end
end
