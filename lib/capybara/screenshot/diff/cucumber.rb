# frozen_string_literal: true

require "capybara/screenshot/diff"
require "capybara/screenshot/diff/test_methods"

World(Capybara::Screenshot::Diff::TestMethods)

Before do
  Capybara::Screenshot::Diff.delayed = false
  Capybara::Screenshot::BrowserHelpers.resize_to(Capybara::Screenshot.window_size) if Capybara::Screenshot.window_size
end
