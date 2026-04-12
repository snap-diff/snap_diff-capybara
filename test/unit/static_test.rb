# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff/static"

module CapybaraScreenshotDiff
  class StaticTest < ActiveSupport::TestCase
    teardown do
      Capybara.app = Rails.application
    end

    test ".serve sets Capybara.app to serve the directory" do
      CapybaraScreenshotDiff.serve("test/fixtures")

      assert_kind_of Rack::Files, Capybara.app
    end

    test ".serve sets Screenshot.root to pwd" do
      CapybaraScreenshotDiff.serve("test/fixtures")

      assert_equal Pathname(Dir.pwd), Capybara::Screenshot.root
    end

    test ".serve accepts custom root" do
      CapybaraScreenshotDiff.serve("test/fixtures", root: "/tmp")

      assert_equal Pathname("/tmp"), Capybara::Screenshot.root
    end
  end
end
