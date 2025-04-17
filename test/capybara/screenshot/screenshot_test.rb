# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module Capybara
  class ScreenshotTest < ActionDispatch::IntegrationTest
    def test_screenshot_area_abs_is_absolute
      assert CapybaraScreenshotDiff::SnapManager.root.absolute?
    end

    def test_root_is_a_pathname
      # NOTE: We test that Rails.root is Pathname, which is true.
      assert_kind_of Pathname, Capybara::Screenshot.root
      assert Capybara::Screenshot.root.absolute?
    end

    def test_root_could_be_assigned_relative_path
      @orig_root = Capybara::Screenshot.root

      Capybara::Screenshot.root = "./tmp"
      assert_kind_of Pathname, Capybara::Screenshot.root
      assert Capybara::Screenshot.root.absolute?
    ensure
      Capybara::Screenshot.root = @orig_root
    end
  end
end
