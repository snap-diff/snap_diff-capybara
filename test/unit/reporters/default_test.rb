# frozen_string_literal: true

require "test_helper"
require "snap_diff/reporters/default"

require "capybara/screenshot/diff/drivers/vips_driver" if defined?(Vips)

module Capybara::Screenshot::Diff
  class Reporters::DefaultTest < ActiveSupport::TestCase
    setup do
      skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
      @_tmpdir = Pathname.new(Dir.mktmpdir)
    end

    teardown do
      FileUtils.remove_entry @_tmpdir if @_tmpdir
    end

    test "for vips driver generates heatmap diff file" do
      driver = SnapDiff::Drivers::VipsDriver.new
      comparison = build_comparison_for(driver, "a.png", "b.png")
      reporter = SnapDiff::Reporters::Default.new(driver.find_difference_region(comparison))

      reporter.generate

      assert_same_images "a-and-b.heatmap.diff.png", reporter.heatmap_diff_path
    end

    test "#clean_tmp_files removes heatmap diff along with other diff artifacts" do
      driver = SnapDiff::Drivers::VipsDriver.new
      comparison = build_comparison_for(driver, "a.png", "b.png")
      reporter = SnapDiff::Reporters::Default.new(driver.find_difference_region(comparison))
      reporter.generate

      assert_predicate reporter.heatmap_diff_path, :exist?

      reporter.clean_tmp_files

      assert_not reporter.annotated_image_path.exist?, "diff should be cleaned"
      assert_not reporter.annotated_base_image_path.exist?, "base diff should be cleaned"
      assert_not reporter.heatmap_diff_path.exist?, "heatmap diff should be cleaned"
    end

    test "failure message reports metrics without leaking image objects" do
      driver = SnapDiff::Drivers::VipsDriver.new
      comparison = build_comparison_for(driver, "a.png", "b.png")
      difference = driver.find_difference_region(comparison)
      difference.meta[:difference_level] = 0.42

      message = SnapDiff::Reporters::Default.new(difference).generate
      metrics = message.lines.first

      assert_includes metrics, "area_size"
      assert_includes metrics, "region"
      assert_includes metrics, "difference_level"
      assert_not_includes metrics, "Vips::Image"
      assert_not_includes metrics, "0x"
    end

    private

    def build_comparison_for(driver, *images)
      new_image = driver.from_file(TEST_IMAGES_DIR.join(images.first))
      base_image = driver.from_file(TEST_IMAGES_DIR.join(images.last))

      SnapDiff::Comparison::Images.new(new_image, base_image, {}, driver, @_tmpdir / images.first, @_tmpdir / images.last)
    end
  end
end
