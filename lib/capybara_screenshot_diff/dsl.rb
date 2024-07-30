# frozen_string_literal: true

require "capybara_screenshot_diff"
require "capybara/screenshot/diff/test_methods"

module CapybaraScreenshotDiff
  module DSL
    include Capybara::DSL
    include Capybara::Screenshot::Diff::TestMethods
  end
end
