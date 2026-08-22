# frozen_string_literal: true

require "capybara_screenshot_diff/dsl"

World(::CapybaraScreenshotDiff::DSL)

Before do
  Capybara::Screenshot::Diff.delayed = false
  Capybara::Screenshot::BrowserHelpers.resize_window_if_needed
end

After do |scenario|
  if !scenario.failed? && Capybara::Screenshot::Diff.pending_if_new && CapybaraScreenshotDiff.new_screenshots_present?
    names = CapybaraScreenshotDiff.new_screenshots
    skip_this_scenario("No baseline for: #{names.join(", ")}. Commit the captured screenshots to record them.")
  end
ensure
  CapybaraScreenshotDiff.reset
end

AfterAll { CapybaraScreenshotDiff.finalize_reporters! }
