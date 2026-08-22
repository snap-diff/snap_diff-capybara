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

    test "#save_annotation_for bakes in a visibly different image when a skip_area is set" do
      skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
      driver = Drivers::VipsDriver.new
      new_image = driver.from_file(TEST_IMAGES_DIR.join("a.png"))
      base_image = driver.from_file(TEST_IMAGES_DIR.join("b.png"))

      with_skip_area = Comparison.new(new_image, base_image, {skip_area: [Region.new(0, 0, 10, 10)]}, driver,
        @_tmpdir / "with_skip_area.png", @_tmpdir / "with_skip_area_base.png")
      without_skip_area = Comparison.new(new_image, base_image, {}, driver,
        @_tmpdir / "without_skip_area.png", @_tmpdir / "without_skip_area_base.png")

      service_with = AnnotationService.new(driver.find_difference_region(with_skip_area))
      service_without = AnnotationService.new(driver.find_difference_region(without_skip_area))
      service_with.annotate_and_save_images
      service_without.annotate_and_save_images

      assert_not FileUtils.compare_file(service_with.annotated_base_image_path.to_s, service_without.annotated_base_image_path.to_s),
        "annotated base image should differ once a skip_area rectangle is drawn onto it"
    end

    private

    def build_comparison_for(driver, *images)
      new_image = driver.from_file(TEST_IMAGES_DIR.join(images.first))
      base_image = driver.from_file(TEST_IMAGES_DIR.join(images.last))

      Comparison.new(new_image, base_image, {}, driver, @_tmpdir / images.first, @_tmpdir / images.last)
    end
  end
end
