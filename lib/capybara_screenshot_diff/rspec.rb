# frozen_string_literal: true

require "rspec/core"
require "capybara_screenshot_diff"

module Capybara::Screenshot::Diff
  ASSERTION = ::StandardError unless defined?(::Capybara::Screenshot::Diff::ASSERTION)
end

RSpec.configure do |config|
  config.include ::Capybara::Screenshot::Diff::TestMethods, type: :feature

  config.after do
    if self.class.include?(::Capybara::Screenshot::Diff::TestMethods) && ::Capybara::Screenshot.active? && ::Capybara::Screenshot::Diff.fail_on_difference
      validate_screenshots!(@test_screenshots)
    end
  end

  config.before do
    if self.class.include?(::Capybara::Screenshot::Diff::TestMethods) && ::Capybara::Screenshot.window_size
      ::Capybara::Screenshot::BrowserHelpers.resize_to(::Capybara::Screenshot.window_size)
    end
  end
end
