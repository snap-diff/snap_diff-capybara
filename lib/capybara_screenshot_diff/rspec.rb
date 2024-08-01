# frozen_string_literal: true

require "rspec/core"
require "capybara_screenshot_diff/dsl"

RSpec::Matchers.define :match_screenshot do |name, **options|
  description { "match a screenshot" }

  match do |_page|
    screenshot(name, **options)
    true
  end
end

RSpec.configure do |config|
  config.include ::CapybaraScreenshotDiff::DSL, type: :feature
  config.include ::CapybaraScreenshotDiff::DSL, type: :system

  config.after do
    if self.class.include?(::CapybaraScreenshotDiff::DSL) && ::Capybara::Screenshot.active?
      errors = verify_screenshots!(@test_screenshots)
      # TODO: Use rspec/mock approach to postpone verification
      raise ::CapybaraScreenshotDiff::ExpectationNotMet, errors.join("\n") if errors && !errors.empty?
    end
  end

  config.before do
    if self.class.include?(::CapybaraScreenshotDiff::DSL) && ::Capybara::Screenshot.window_size
      ::Capybara::Screenshot::BrowserHelpers.resize_to(::Capybara::Screenshot.window_size)
    end
  end
end
