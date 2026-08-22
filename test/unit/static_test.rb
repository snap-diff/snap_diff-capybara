# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff/static"

module CapybaraScreenshotDiff
  class StaticTest < ActiveSupport::TestCase
    setup do
      @original_root = Capybara::Screenshot.root
    end

    teardown do
      Capybara.app = Rails.application
      Capybara::Screenshot.root = @original_root
    end

    test ".serve sets Capybara.app to serve the directory" do
      SnapDiff.serve("test/fixtures")

      assert_kind_of Rack::Files, Capybara.app
    end

    test ".serve sets Screenshot.root to pwd" do
      SnapDiff.serve("test/fixtures")

      assert_equal Pathname(Dir.pwd), Capybara::Screenshot.root
    end

    test ".serve accepts custom root (via the legacy CapybaraScreenshotDiff.serve forwarder)" do
      # Deliberate legacy-surface use: pins that the old entry still forwards.
      CapybaraScreenshotDiff.serve("test/fixtures", root: "/tmp")

      assert_equal Pathname("/tmp"), Capybara::Screenshot.root
    end
  end
end
