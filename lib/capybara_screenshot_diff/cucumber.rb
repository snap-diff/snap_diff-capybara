# frozen_string_literal: true

require "capybara_screenshot_diff/dsl"

World(::CapybaraScreenshotDiff::DSL)

Before do
  Capybara::Screenshot::Diff.delayed = false
  if Capybara::Screenshot.active? && Capybara::Screenshot.window_size
    Capybara::Screenshot::BrowserHelpers.resize_to(Capybara::Screenshot.window_size)
  end
end
