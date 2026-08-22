# frozen_string_literal: true

require "capybara_screenshot_diff/dsl"

World(::CapybaraScreenshotDiff::DSL)

Before do
  Capybara::Screenshot::Diff.delayed = false
  Capybara::Screenshot::BrowserHelpers.resize_window_if_needed
end

After do |scenario|
  if !scenario.failed? && (msg = CapybaraScreenshotDiff.pending_screenshots_message)
    skip_this_scenario(msg)
  end
ensure
  CapybaraScreenshotDiff.reset
end

AfterAll { CapybaraScreenshotDiff.finalize_reporters! }
