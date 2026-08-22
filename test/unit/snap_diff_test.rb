# frozen_string_literal: true

require "test_helper"

class SnapDiffTest < ActiveSupport::TestCase
  test "SnapDiff::Comparison aliases Capybara::Screenshot::Diff::ImageCompare" do
    assert_same Capybara::Screenshot::Diff::ImageCompare, SnapDiff::Comparison
  end

  test ".compare returns the same kind of result as Diff.compare" do
    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "a.png"
    )

    assert_kind_of Capybara::Screenshot::Diff::ImageCompare, result
    assert result.quick_equal?
  end

  test ".start yields the same objects Diff.configure yields" do
    yielded = []
    Capybara::Screenshot::Diff.configure { |screenshot, diff| yielded << [screenshot, diff] }

    started = []
    SnapDiff.start { |screenshot, diff| started << [screenshot, diff] }

    assert_equal yielded, started
  end

  test ".start applies a setting like Diff.configure does" do
    original = Capybara::Screenshot::Diff.tolerance

    begin
      SnapDiff.start { |_screenshot, diff| diff.tolerance = 0.0123 }

      assert_equal 0.0123, Capybara::Screenshot::Diff.tolerance
    ensure
      Capybara::Screenshot::Diff.tolerance = original
    end
  end
end
