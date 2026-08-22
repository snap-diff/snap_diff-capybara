# frozen_string_literal: true

# Legacy entry point: pre-move, this path transitively loaded the whole gem
# (via dsl -> umbrella). Preserve that contract for consumers who require
# only this file.
require "capybara_screenshot_diff"

require "snap_diff/integrations/minitest"

module CapybaraScreenshotDiff
  module Minitest
    Assertions = SnapDiff::Minitest::Assertions
  end
end
