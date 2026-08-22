# frozen_string_literal: true

require "rspec/core"
require "capybara_screenshot_diff/dsl"

RSpec::Matchers.define :match_screenshot do |name, **options|
  description { "match screenshot '#{name}'" }

  match do |_page|
    assert_matches_screenshot(name, **options)
    true
  end

  failure_message do
    "Expected page to match screenshot '#{name}'"
  end

  failure_message_when_negated do
    "Expected page not to match screenshot '#{name}'"
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

  config.after do |example|
    if self.class.include?(CapybaraScreenshotDiff::DSL)
      begin
        CapybaraScreenshotDiff.verify

        # Never mask a real failure with a pending marker.
        if example.exception.nil? && Capybara::Screenshot::Diff.pending_if_new && CapybaraScreenshotDiff.new_screenshots_present?
          names = CapybaraScreenshotDiff.new_screenshots
          skip "No baseline for: #{names.join(", ")}. Commit the captured screenshots to record them."
        end
      rescue CapybaraScreenshotDiff::ExpectationNotMet => e
        raise RSpec::Expectations::ExpectationNotMetError.new(e.message).tap { |ex| ex.set_backtrace(e.backtrace) }
      ensure
        CapybaraScreenshotDiff.reset
      end
    end
  end

  config.after(:suite) { CapybaraScreenshotDiff.finalize_reporters! }
end
