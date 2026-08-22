# frozen_string_literal: true

require "snap_diff/browser_helpers"

module Capybara
  module Screenshot
    BrowserHelpers = SnapDiff::BrowserHelpers
  end
end
