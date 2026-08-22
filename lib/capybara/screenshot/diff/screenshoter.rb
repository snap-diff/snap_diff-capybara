# frozen_string_literal: true

require "snap_diff/screenshoter"

module Capybara
  module Screenshot
    Screenshoter = SnapDiff::Screenshoter
  end
end
