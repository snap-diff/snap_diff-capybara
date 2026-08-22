# frozen_string_literal: true

require "test_helper"
require "open3"

class SnapDiffTest < ActiveSupport::TestCase
  test "SnapDiff::Comparison aliases Capybara::Screenshot::Diff::ImageCompare" do
    assert_same Capybara::Screenshot::Diff::ImageCompare, SnapDiff::Comparison
  end

  test ".compare returns the same kind of result as Diff.compare, forwarding options" do
    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "b.png",
      tolerance: 0.02
    )

    assert_kind_of Capybara::Screenshot::Diff::ImageCompare, result
    assert_equal 0.02, result.driver_options[:tolerance]
  end

  # Regression test for a load-order bug: `require "snap_diff"` standalone
  # (nothing else preloaded) used to raise
  # `NameError: uninitialized constant ...ImageCompare::Drivers` because
  # image_compare.rb called Drivers.for without requiring drivers.rb.
  # test_helper.rb preloads the whole gem, so only a subprocess with a
  # fresh load path can catch this class of bug.
  test "require \"snap_diff\" is standalone-loadable in a fresh process" do
    script = <<~RUBY
      require "snap_diff"
      result = SnapDiff.compare(#{(TEST_IMAGES_DIR / "a.png").to_s.inspect}, #{(TEST_IMAGES_DIR / "b.png").to_s.inspect})
      exit(result.is_a?(SnapDiff::Comparison) ? 0 : 1)
    RUBY

    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, "expected standalone `require \"snap_diff\"` to succeed, got:\n#{out}"
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
