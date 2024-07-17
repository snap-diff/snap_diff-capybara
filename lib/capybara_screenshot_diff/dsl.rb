# frozen_string_literal: true

require "capybara_screenshot_diff"

module CapybaraScreenshotDiff
  module DSL
    include Capybara::DSL
    include Capybara::Screenshot::Diff::TestMethods
  end
end
