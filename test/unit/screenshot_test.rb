# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ScreenshotTest < ActiveSupport::TestCase
  test "SnapManager.root returns an absolute path" do
    assert SnapDiff::SnapManager.root.absolute?
  end

  test "Screenshot.root returns a Pathname when Rails.root is a Pathname" do
    # NOTE: We test that Rails.root is Pathname, which is true.
    assert_kind_of Pathname, SnapDiff.config.root
    assert SnapDiff.config.root.absolute?
  end

  test "Screenshot.root can be set to a relative path and is converted to absolute" do
    @orig_root = SnapDiff.config.root

    SnapDiff.config.root = "./tmp"
    assert_kind_of Pathname, SnapDiff.config.root
    assert SnapDiff.config.root.absolute?
  ensure
    SnapDiff.config.root = @orig_root if @orig_root
  end
end
