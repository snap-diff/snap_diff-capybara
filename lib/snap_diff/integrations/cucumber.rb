# frozen_string_literal: true

# See the matching comment in integrations/minitest.rb.
require_relative "../dsl"
require "capybara_screenshot_diff/screenshot_assertion"

World(::SnapDiff::DSL)

Before do
  Capybara::Screenshot::Diff.delayed = false
  SnapDiff::BrowserHelpers.resize_window_if_needed
end

After do |scenario|
  if !scenario.failed? && (msg = CapybaraScreenshotDiff.pending_screenshots_message)
    skip_this_scenario(msg)
  end
ensure
  CapybaraScreenshotDiff.reset
end

AfterAll { CapybaraScreenshotDiff.finalize_reporters! }
