# frozen_string_literal: true

require "test_helper"

unless defined?(Vips)
  warn "VIPS not present. Skipping VIPS driver tests."
  return
end

require "capybara/screenshot/diff/drivers/vips_driver"

module Capybara
  module Screenshot
    module Diff
      module Drivers
        class VipsDriverTest < ActiveSupport::TestCase
          include CapybaraScreenshotDiff::DSLStub

          setup do
            @new_screenshot_result = Tempfile.new(%w[screenshot .png], Rails.root)
          end

          teardown do
            if @new_screenshot_result
              @new_screenshot_result.close
              @new_screenshot_result.unlink
            end

            Vips.cache_set_max(0)
            Vips.cache_set_max(1000)
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

        class VipsUtilTest < ActiveSupport::TestCase
          test "VipsUtil.difference_region_by detects difference regions without color threshold" do
            old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
            new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/b.png")

            left, top, right, bottom = difference(old_image, new_image)

            assert_equal [20.0, 15.0, 30.0, 25.0], [left, top, right, bottom]

            left, top, right, bottom = difference(old_image, new_image, color_distance: 0)

            assert_equal [20.0, 15.0, 30.0, 25.0], [left, top, right, bottom]
          end

          test "VipsUtil.difference_region_by respects color_distance threshold" do
            old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
            new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/b.png")

            left, top, right, bottom = difference(old_image, new_image, color_distance: 150)

            assert_equal [26.0, 18.0, 27.0, 19.0], [left, top, right, bottom]
          end

          test "VipsUtil.difference_region_by returns correct region coordinates" do
            old_image = Vips::Image.new_from_file(TEST_IMAGES_DIR.join("a.png").to_path)
            new_image = Vips::Image.new_from_file(TEST_IMAGES_DIR.join("b.png").to_path)

            left, top, right, bottom = difference(old_image, new_image)

            assert_equal [20.0, 15.0, 30.0, 25.0], [left, top, right, bottom]
          end

          test "VipsUtil.difference_area calculates correct area of difference" do
            old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
            new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/d.png").bandjoin(255)

            assert_equal 8, VipsDriver::VipsUtil.difference_area(old_image, new_image, color_distance: 10)
          end

          private

          def difference(old_image, new_image, color_distance: nil)
            diff_mask = VipsDriver::VipsUtil.difference_mask(new_image, old_image, color_distance)
            VipsDriver::VipsUtil.difference_region_by(diff_mask).to_edge_coordinates
          end
        end
      end
    end
  end
end
