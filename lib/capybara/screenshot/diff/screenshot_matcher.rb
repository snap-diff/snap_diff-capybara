# frozen_string_literal: true

require "snap_diff/screenshot_matcher"

module Capybara
  module Screenshot
    module Diff
      ScreenshotMatcher = SnapDiff::ScreenshotMatcher
    end
  end
end
