# frozen_string_literal: true

require "test_helper"
require "support/driver_contract_tests"

require "snap_diff/drivers/vips_driver" if defined?(Vips)

# Nested in the canonical SnapDiff::Drivers namespace: reopening the old
# Capybara::Screenshot::Diff::Drivers path would define a fresh Drivers
# module there, shadowing the v2 step 6 lazy const_missing forwarder.
module SnapDiff
  module Drivers
    class VipsDriverTest < ActiveSupport::TestCase
      include DSLStub
      include DriverContractTests

      setup do
        skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
        @new_screenshot_result = Tempfile.new(%w[screenshot .png], Rails.root)
      end

      teardown do
        if @new_screenshot_result
          @new_screenshot_result.close
          @new_screenshot_result.unlink
        end

        if defined?(Vips)
          Vips.cache_set_max(0)
          Vips.cache_set_max(1000)
        end
      end

      test "#different? returns false when comparing identical images" do
        comp = make_comparison(:a, :a)
        assert_not comp.different?
      end

      test "#quick_equal? returns true when comparing identical images" do
        comp = make_comparison(:a, :a)

        assert comp.quick_equal?
      end

      test "can be instantiated with default constructor" do
        assert VipsDriver.new
      end

      test "#different? preserves runtime files when images are different" do
        comp = make_comparison(:a, :c)
        assert comp.different?
        assert_includes comp.error_message, "[11.0,3.0,49.0,21.0]"
        assert File.exist?(comp.base_image_path)
        assert File.exist?(comp.reporter.annotated_base_image_path)
        assert File.exist?(comp.reporter.annotated_image_path)
      end

      test "#different? cleans up runtime files when images are identical" do
        comp = make_comparison(:c, :c)
        assert_not comp.different?

        assert comp.reporter.annotated_base_image_path
        assert comp.reporter.annotated_image_path

        assert_not File.exist?(comp.reporter.annotated_base_image_path)
        assert_not File.exist?(comp.reporter.annotated_image_path)
      end

      test "#different? detects single-pixel wide differences between images" do
        comp = make_comparison(:a, :d)
        assert comp.different?
        assert_includes comp.error_message, "[9.0,6.0,10.0,14.0]"
      end

      test "#different? respects color_distance_limit when within allowed threshold" do
        comp = make_comparison(:a, :b, color_distance_limit: 255)
        assert_not comp.different?
      end

      test "#different? enforces color_distance_limit when beyond allowed threshold" do
        comp = make_comparison(:a, :b, color_distance_limit: 3)
        assert comp.different?
      end

      test "#different? returns equal when tolerance is greater than difference area" do
        comp = make_comparison(:a, :b, tolerance: 0.01)
        assert comp.quick_equal?
        assert_not comp.different?
        assert_not comp.error_message
      end

      test "#different? detects difference when tolerance is less than difference area" do
        comp = make_comparison(:a, :b, tolerance: 0.000001)
        assert_not comp.quick_equal?
        assert comp.different?
      end

      test "#different? handles single-pixel line differences with median filter" do
        comp = make_comparison(:a, :d, median_filter_window_size: 3, color_distance_limit: 8)
        assert comp.quick_equal?
        assert_not comp.different?
      end

      test "#quick_equal? returns false when images are different" do
        comp = make_comparison(:a, :b)
        assert_not comp.quick_equal?
      end

      test "#quick_equal? respects color_distance_limit when below difference threshold" do
        comp = make_comparison(:a, :b, color_distance_limit: 2)
        assert_not comp.quick_equal?
      end

      test "#quick_equal? respects color_distance_limit when above difference threshold" do
        comp = make_comparison(:a, :b, color_distance_limit: 200)
        assert comp.quick_equal?
      end

      test "#different? detects dimension changes between images" do
        comp = make_comparison(:a, :a_cropped)
        assert comp.different?
        assert_includes comp.error_message, "Dimensions have changed: "
        assert_includes comp.error_message, "80x60"
      end

      test "#quick_equal? skips differences covered by skip_area configuration" do
        comp = make_comparison(
          :a,
          :d,
          skip_area: [
            Region.from_edge_coordinates(9, 0, 11, 80),
            Region.from_edge_coordinates(79, 79, 80, 80)
          ]
        )
        assert comp.quick_equal?
        assert_not comp.different?
      end

      test "#quick_equal? detects differences not covered by skip_area" do
        comp = make_comparison(
          :a,
          :d,
          skip_area: [
            Region.from_edge_coordinates(79, 79, 80, 80),
            Region.from_edge_coordinates(78, 78, 80, 80)
          ]
        )
        assert_not comp.quick_equal?
        assert comp.different?
      end

      test "#different? uses perceptual_threshold when set" do
        comp = make_comparison(:a, :b, perceptual_threshold: 2.0)
        assert comp.different?
      end

      test "#different? with perceptual_threshold returns equal for identical images" do
        comp = make_comparison(:a, :a, perceptual_threshold: 2.0)
        assert_not comp.different?
      end

      # Test Interface Contracts

      test "#from_file successfully loads an image from the specified path" do
        assert VipsDriver.new.from_file(TEST_IMAGES_DIR / "a.png")
      end

      private

      def make_comparison(old_img, new_img, options = {})
        destination = Pathname.new(@new_screenshot_result.path)
        super(old_img, new_img, destination: destination, **options.merge(driver: :vips))
      end

      def sample_region
        [0, 0, 0, 0]
      end
    end

    class VipsDriverClassMethodsTest < ActiveSupport::TestCase
      setup do
        skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
      end

      test "VipsDriver.difference_region_by detects difference regions without color threshold" do
        old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
        new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/b.png")

        left, top, right, bottom = difference(old_image, new_image)

        assert_equal [20.0, 15.0, 30.0, 25.0], [left, top, right, bottom]

        left, top, right, bottom = difference(old_image, new_image, color_distance: 0)

        assert_equal [20.0, 15.0, 30.0, 25.0], [left, top, right, bottom]
      end

      test "VipsDriver.difference_region_by respects color_distance threshold" do
        old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
        new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/b.png")

        left, top, right, bottom = difference(old_image, new_image, color_distance: 150)

        assert_equal [26.0, 18.0, 27.0, 19.0], [left, top, right, bottom]
      end

      test "VipsDriver.difference_region_by returns correct region coordinates" do
        old_image = Vips::Image.new_from_file(TEST_IMAGES_DIR.join("a.png").to_path)
        new_image = Vips::Image.new_from_file(TEST_IMAGES_DIR.join("b.png").to_path)

        left, top, right, bottom = difference(old_image, new_image)

        assert_equal [20.0, 15.0, 30.0, 25.0], [left, top, right, bottom]
      end

      test "VipsDriver.perceptual_difference_mask returns nil region for identical images" do
        old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
        same_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")

        diff_mask = VipsDriver.perceptual_difference_mask(old_image, same_image)
        region = VipsDriver.difference_region_by(diff_mask)

        assert_nil region
      end

      test "VipsDriver.perceptual_difference_mask detects differences between images" do
        old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
        new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/b.png")

        diff_mask = VipsDriver.perceptual_difference_mask(old_image, new_image, 2.0)
        region = VipsDriver.difference_region_by(diff_mask)

        assert_not_nil region
      end

      test "VipsDriver.perceptual_difference_mask detects alpha channel differences" do
        old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
        # Make a copy with different alpha
        transparent = old_image.extract_band(0, n: 3).bandjoin(128)

        diff_mask = VipsDriver.perceptual_difference_mask(old_image, transparent)
        region = VipsDriver.difference_region_by(diff_mask)

        assert_not_nil region, "Should detect alpha channel difference"
      end

      test "VipsDriver.perceptual_difference_mask respects threshold" do
        old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
        new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/b.png")

        # High threshold — fewer differences detected
        high_mask = VipsDriver.perceptual_difference_mask(old_image, new_image, 50.0)
        high_region = VipsDriver.difference_region_by(high_mask)

        # Low threshold — more differences detected
        low_mask = VipsDriver.perceptual_difference_mask(old_image, new_image, 2.0)
        low_region = VipsDriver.difference_region_by(low_mask)

        assert_not_nil low_region
        # High threshold region should be smaller or nil compared to low threshold
        if high_region
          assert high_region.size <= low_region.size
        end
      end

      private

      def difference(old_image, new_image, color_distance: nil)
        diff_mask = VipsDriver.difference_mask(new_image, old_image, color_distance)
        VipsDriver.difference_region_by(diff_mask).to_edge_coordinates
      end
    end
  end
end
