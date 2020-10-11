# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/drivers/vips_driver"

module Capybara
  module Screenshot
    module Diff
      module Drivers
        class VipsDriverTest < ActionDispatch::IntegrationTest
          include TestHelper

          setup do
            @new_screenshot_result = Tempfile.new(%w[screenshot .png], Rails.root)
          end

          teardown do
            if @new_screenshot_result
              @new_screenshot_result.close
              @new_screenshot_result.unlink
            end
          end

          test "#different? for equal is negative" do
            comp = make_comparison(:a, :a)
            assert_not comp.different?
          end

          test "#quick_equal? for equal is positive" do
            comp = make_comparison(:a, :a)

            assert comp.quick_equal?
          end

          test "it can be instantiated" do
            assert VipsDriver.new("images/b.png")
          end

          test "it can be instantiated with dimensions" do
            assert VipsDriver.new("images/b.png", dimensions: [80, 80])
          end

          test "when different does not clean runtime files" do
            comp = make_comparison(:a, :c)
            assert comp.different?
            assert_equal [11.0, 3.0, 49.0, 21.0], comp.dimensions
            assert File.exist?(comp.old_file_name)
            assert File.exist?(comp.annotated_old_file_name)
            assert File.exist?(comp.annotated_new_file_name)
          end

          test "when equal clean runtime files" do
            comp = make_comparison(:c, :c)
            assert_not comp.different?
            assert_not File.exist?(comp.old_file_name)
            assert_not File.exist?(comp.annotated_old_file_name)
            assert_not File.exist?(comp.annotated_new_file_name)
          end

          test "compare of 1 pixel wide diff" do
            comp = make_comparison(:a, :d)
            assert comp.different?
            assert_equal [9.0, 6.0, 10.0, 14.0], comp.dimensions
          end

          test "compare with color_distance_limit above difference" do
            comp = make_comparison(:a, :b, color_distance_limit: 255)
            assert_not comp.different?
          end

          test "compare with color_distance_limit below difference" do
            comp = make_comparison(:a, :b, color_distance_limit: 3)
            assert comp.different?
          end

          test "compare with tolerance level more then area of the difference" do
            comp = make_comparison(:a, :b, tolerance: 0.01)
            assert comp.quick_equal?
            assert_not comp.different?
          end

          test "compare with tolerance level less then area of the difference" do
            comp = make_comparison(:a, :b, tolerance: 0.000001)
            assert_not comp.quick_equal?
            assert comp.different?
          end

          test "compare with median_filter_window_size when images have 1px line difference" do
            comp = make_comparison(:a, :d, median_filter_window_size: 3, color_distance_limit: 8)
            assert comp.quick_equal?
            assert_not comp.different?
          end

          test "quick_equal compare with shift_distance_limit above difference" do
            comp = make_comparison(:a, :d, shift_distance_limit: 11)
            assert comp.quick_equal?
          end

          test "different with shift_distance_limit above difference" do
            comp = make_comparison(:a, :d, shift_distance_limit: 11)
            assert_not comp.different?
          end

          test "quick_equal? with shift_distance_limit below difference" do
            comp = make_comparison(:a, :b, shift_distance_limit: 9)
            assert_not comp.quick_equal?
          end

          test "different? with shift_distance_limit below difference" do
            comp = make_comparison(:a, :b, shift_distance_limit: 9)
            assert comp.different?
          end

          test "quick_equal" do
            comp = make_comparison(:a, :b)
            assert_not comp.quick_equal?
          end

          test "quick_equal with color distance limit below current level" do
            comp = make_comparison(:a, :b, color_distance_limit: 2)
            assert_not comp.quick_equal?
          end

          test "quick_equal with color distance limit above current level" do
            comp = make_comparison(:a, :b, color_distance_limit: 200)
            assert comp.quick_equal?
          end

          test "size a vs a_cropped" do
            comp = make_comparison(:a, :a_cropped)
            comp.different?
            assert_equal 6400, comp.size
          end

          test "quick_equal compare skips difference if skip_area covers it" do
            comp = make_comparison(:a, :d, skip_area: [[9, 0, 11, 80], [79, 79, 80, 80]])
            assert comp.quick_equal?
            assert_not comp.different?
          end

          test "quick_equal compare skips difference if skip_area does not cover it" do
            comp = make_comparison(:a, :d, skip_area: [[79, 79, 80, 80], [78, 78, 80, 80]])
            assert_not comp.quick_equal?
            assert comp.different?
          end

          private

          def make_comparison(old_img, new_img, **driver_args)
            result = VipsDriver.new(@new_screenshot_result.path, **driver_args)
            set_test_images(result, old_img, new_img)
            result
          end
        end

        class VipsUtilTest < ActiveSupport::TestCase
          test "segment difference without min color difference" do
            old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
            new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/b.png")

            left, top, right, bottom = VipsDriver::VipsUtil.difference(old_image, new_image)

            assert_equal [20.0, 15.0, 30.0, 25.0], [left, top, right, bottom]
          end

          test "segment difference" do
            old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
            new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/b.png")

            left, top, right, bottom = VipsDriver::VipsUtil.difference(old_image, new_image)

            assert_equal [20.0, 15.0, 30.0, 25.0], [left, top, right, bottom]
          end

          test "area of the difference" do
            old_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/a.png")
            new_image = Vips::Image.new_from_file("#{TEST_IMAGES_DIR}/d.png").bandjoin(255)

            assert_equal 8, VipsDriver::VipsUtil.difference_area(old_image, new_image, color_distance: 10)
          end
        end
      end
    end
  end
end
