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

  test ".compare accepts driver option" do
    skip "VIPS not present" unless defined?(Vips)

    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "a.png",
      driver: :vips
    )
    assert result.quick_equal?
  end

  test ".compare accepts tolerance options" do
    skip "VIPS not present" unless defined?(Vips)

    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "b.png",
      driver: :vips,
      tolerance: 1.0
    )
    assert_not result.different?
  end

  # The capture can vanish between capture and comparison (two tests writing
  # the same screenshot name, a cleanup racing the run). That is a difference
  # to report, not a crash: `different?` used to raise TypeError because the
  # missing-image result carried a String where every reader indexes a Hash.
  test "a capture that disappears before the comparison runs reads as different" do
    Dir.mktmpdir do |dir|
      base = Pathname(dir) / "x.base.png"
      capture = Pathname(dir) / "x.png"
      FileUtils.cp TEST_IMAGES_DIR / "a.png", base
      FileUtils.cp TEST_IMAGES_DIR / "b.png", capture
      comparison = SnapDiff.compare(base, capture)
      FileUtils.rm capture

      assert comparison.different?
      assert_match(/missing: actual .*x\.png/, comparison.error_message)
    end
  end

  # quick_equal? destructures find_difference's answer into [equal, result].
  # The missing-image path used to return the bare result, which a Struct
  # splits into its fields, so `difference` ended up holding the meta Hash
  # and the next `different?` raised NoMethodError.
  test "#quick_equal? on a vanished capture is false and leaves a usable difference" do
    Dir.mktmpdir do |dir|
      base = Pathname(dir) / "x.base.png"
      capture = Pathname(dir) / "x.png"
      FileUtils.cp TEST_IMAGES_DIR / "a.png", base
      FileUtils.cp TEST_IMAGES_DIR / "b.png", capture
      comparison = SnapDiff.compare(base, capture)
      FileUtils.rm capture

      assert_not comparison.quick_equal?
      assert comparison.different?
      assert comparison.difference.failed_by[:missing_image]
    end
  end
end
