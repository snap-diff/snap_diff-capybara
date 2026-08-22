# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/annotation_service"

unless defined?(Vips)
  warn "VIPS not present. Skipping VIPS driver tests."
  return
end
require "capybara/screenshot/diff/drivers/vips_driver"

module Capybara::Screenshot::Diff
  class AnnotationServiceTest < ActiveSupport::TestCase
    setup do
      @_tmpdir = Pathname.new(Dir.mktmpdir)
    end

    teardown do
      FileUtils.remove_entry @_tmpdir if @_tmpdir
    end

    test "#annotate_and_save_images writes annotated and heatmap images" do
      skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
      driver = Drivers::VipsDriver.new
      comparison = build_comparison_for(driver, "a.png", "b.png")
      service = AnnotationService.new(driver.find_difference_region(comparison))

      service.annotate_and_save_images

      assert_same_images "a-and-b.heatmap.diff.png", service.heatmap_diff_path
    end

    test "#clean_tmp_files removes annotated and heatmap images" do
      skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
      driver = Drivers::VipsDriver.new
      comparison = build_comparison_for(driver, "a.png", "b.png")
      service = AnnotationService.new(driver.find_difference_region(comparison))
      service.annotate_and_save_images

      assert_predicate service.heatmap_diff_path, :exist?

      service.clean_tmp_files

      assert_not service.annotated_image_path.exist?, "diff should be cleaned"
      assert_not service.annotated_base_image_path.exist?, "base diff should be cleaned"
      assert_not service.heatmap_diff_path.exist?, "heatmap diff should be cleaned"
    end

    private

    def build_comparison_for(driver, *images)
      new_image = driver.from_file(TEST_IMAGES_DIR.join(images.first))
      base_image = driver.from_file(TEST_IMAGES_DIR.join(images.last))

      Comparison.new(new_image, base_image, {}, driver, @_tmpdir / images.first, @_tmpdir / images.last)
    end
  end
end
