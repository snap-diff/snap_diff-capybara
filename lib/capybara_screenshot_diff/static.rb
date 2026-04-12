# frozen_string_literal: true

require "rack/files"
require "capybara_screenshot_diff/minitest"

module CapybaraScreenshotDiff
  def self.serve(directory, root: Dir.pwd)
    Capybara.app = Rack::Files.new(directory)
    Capybara::Screenshot.root = root
  end
end
