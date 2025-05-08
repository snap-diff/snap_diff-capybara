# frozen_string_literal: true

require "capybara_screenshot_diff"
require "capybara/screenshot/diff/test_methods"
require_relative "screenshot_assertion"

module CapybaraScreenshotDiff
  module DSL
    include Capybara::DSL
    include Capybara::Screenshot::Diff::TestMethods

    alias_method :_screenshot, :screenshot
    def screenshot(name, **args)
      assertion = CapybaraScreenshotDiff::ScreenshotAssertion.new(name, **args) { _screenshot(name, **args) }
      CapybaraScreenshotDiff.add_assertion(assertion)
    end
  end
end
