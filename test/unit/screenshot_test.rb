# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module Capybara
  class ScreenshotTest < ActiveSupport::TestCase
    test "SnapManager.root returns an absolute path" do
      assert CapybaraScreenshotDiff::SnapManager.root.absolute?
    end

    test "Screenshot.root returns a Pathname when Rails.root is a Pathname" do
      # NOTE: We test that Rails.root is Pathname, which is true.
      assert_kind_of Pathname, Capybara::Screenshot.root
      assert Capybara::Screenshot.root.absolute?
    end

    test "Screenshot.root can be set to a relative path and is converted to absolute" do
      @orig_root = Capybara::Screenshot.root

      Capybara::Screenshot.root = "./tmp"
      assert_kind_of Pathname, Capybara::Screenshot.root
      assert Capybara::Screenshot.root.absolute?
    ensure
      Capybara::Screenshot.root = @orig_root if @orig_root
    end

    test "configure_consistency presets defaults and allows custom injections" do
      Capybara::Screenshot.custom_stylesheets = []
      Capybara::Screenshot.custom_scripts = []

      Capybara::Screenshot.configure_consistency(preset: :off) do |c|
        c.css << ".csd-test { color: red; }"
        c.js << "window.__csd_test = true;"
        c.hide_caret = true
      end

      assert_equal false, Capybara::Screenshot.normalize_css
      assert_equal false, Capybara::Screenshot.wait_for_fonts
      assert_equal false, Capybara::Screenshot.disable_animations
      assert_equal true, Capybara::Screenshot.hide_caret
      assert_equal false, Capybara::Screenshot.blur_active_element
      assert_includes Capybara::Screenshot.custom_stylesheets, ".csd-test { color: red; }"
      assert_includes Capybara::Screenshot.custom_scripts, "window.__csd_test = true;"
    end
  end
end
