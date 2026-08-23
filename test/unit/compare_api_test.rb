# frozen_string_literal: true

require "test_helper"

# The canonical entry point for the file-to-file compare API. The v1
# `Capybara::Screenshot::Diff.compare` forwarder over it is exercised in
# test/legacy/legacy_forwarders_test.rb.
class CompareApiTest < ActiveSupport::TestCase
  test ".compare returns ImageCompare instance" do
    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "a.png"
    )
    assert_kind_of SnapDiff::Comparison, result
  end

  test ".compare detects identical images" do
    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "a.png"
    )
    assert result.quick_equal?
    assert_not result.different?
  end

  test ".compare detects different images" do
    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "b.png"
    )
    assert_not result.quick_equal?
    assert result.different?
  end

  # ".compare accepts driver option" is gone with the option: 2.1 removed
  # driver selection, so there is nothing left to accept.
  test ".compare compares two images with the configured defaults" do
    result = SnapDiff.compare(TEST_IMAGES_DIR / "a.png", TEST_IMAGES_DIR / "a.png")
    assert result.quick_equal?
  end

  test ".compare accepts tolerance options" do
    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "b.png",
      tolerance: 1.0
    )
    assert_not result.different?
  end
end
