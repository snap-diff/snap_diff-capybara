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
  end
end
