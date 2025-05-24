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
  config.include CapybaraScreenshotDiff::DSL, type: :feature
  config.include CapybaraScreenshotDiff::DSL, type: :system

  config.before do
    if self.class.include?(CapybaraScreenshotDiff::DSL)
      Capybara::Screenshot::BrowserHelpers.resize_window_if_needed
    end
  end

  config.after do
    if self.class.include?(CapybaraScreenshotDiff::DSL)
      begin
        CapybaraScreenshotDiff.verify
      rescue CapybaraScreenshotDiff::ExpectationNotMet => e
        raise RSpec::Expectations::ExpectationNotMetError.new(e.message).tap { |ex| ex.set_backtrace(e.backtrace) }
      ensure
        CapybaraScreenshotDiff.reset
      end
    end
  end
end
