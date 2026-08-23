# frozen_string_literal: true

# Legacy entry point: loads the legacy surface (the umbrella) like its
# minitest/rspec/cucumber siblings, so consumers who require only this file
# still get CapybaraScreenshotDiff's session and reporter methods.
require "capybara_screenshot_diff"
require "snap_diff/static"

module CapybaraScreenshotDiff
  def self.serve(...)
    SnapDiff.serve(...)
  end
end
