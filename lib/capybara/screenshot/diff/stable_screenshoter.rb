# frozen_string_literal: true

require "snap_diff/stable_screenshoter"

module Capybara
  module Screenshot
    module Diff
      StableScreenshoter = SnapDiff::StableScreenshoter
    end
  end
end
