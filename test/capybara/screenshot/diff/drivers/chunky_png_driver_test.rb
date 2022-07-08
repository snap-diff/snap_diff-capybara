# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/image_compare"
require "capybara/screenshot/diff/drivers/chunky_png_driver"

module Capybara
  module Screenshot
    module Diff
      module Drivers
        class ChunkyPNGDriverTest < ActionDispatch::IntegrationTest
          include TestHelper

          test "it can be instantiated" do
            assert ChunkyPNGDriver.new("images/b.png")
          end

          test "it can be instantiated with dimensions" do
            assert ChunkyPNGDriver.new("images/b.png", dimensions: [80, 80])
          end

          test "#different? for equal is negative" do
            comp = make_comparison(:a, :a)
            assert_not comp.different?
          end

          test "#quick_equal? for equal is positive" do
            comp = make_comparison(:a, :a)
            assert comp.quick_equal?
          end

          test "compare then dimensions and cleanup" do
            comp = make_comparison(:a, :c)
            assert comp.different?
            assert_equal [11, 3, 48, 20], comp.difference_coordinates
            assert File.exist?(comp.old_file_name)
            assert File.exist?(comp.annotated_old_file_name)
            assert File.exist?(comp.annotated_new_file_name)
            comp = make_comparison(:c, :c)
            assert !comp.different?
            assert !File.exist?(comp.old_file_name)
            assert !File.exist?(comp.annotated_old_file_name)
            assert !File.exist?(comp.annotated_new_file_name)
          end

          test "compare of 1 pixel wide diff" do
            comp = make_comparison(:a, :d)
            assert comp.different?
            assert_equal [9, 6, 9, 13], comp.difference_coordinates
          end

          test "compare with color_distance_limit above difference" do
            comp = make_comparison(:a, :b, color_distance_limit: 223)
            assert_not comp.different?
            assert_equal 223, comp.max_color_distance.ceil
          end

          test "compare with color_distance_limit below difference" do
            comp = make_comparison(:a, :b, color_distance_limit: 222)
            assert comp.different?
            assert_equal 223, comp.max_color_distance.ceil
          end

          test "compare with shift_distance_limit above difference" do
            comp = make_comparison(:a, :b, shift_distance_limit: 11)
            assert_not comp.different?
            assert_equal 0, comp.max_shift_distance.ceil
          end

          test "compare with shift_distance_limit below difference" do
            comp = make_comparison(:a, :b, shift_distance_limit: 9)
            assert comp.different?
            assert_equal 11, comp.max_shift_distance.ceil
          end

          test "quick_equal with color distance limit above max color distance" do
            comp = make_comparison(:a, :b, color_distance_limit: 224)
            assert comp.quick_equal?
            assert_equal 223, comp.max_color_distance.ceil
          end

          test "quick_equal with color distance limit" do
            comp = make_comparison(:a, :b, color_distance_limit: 222)
            assert !comp.quick_equal?
            assert_equal 223, comp.max_color_distance.ceil
          end

          test "max_color_distance a vs b" do
            comp = make_comparison(:a, :b)
            assert_equal 223, comp.max_color_distance.ceil
          end

          test "max_color_distance a vs c" do
            comp = make_comparison(:a, :c)
            assert_equal 318, comp.max_color_distance.ceil
          end

          test "max_color_distance a vs d" do
            comp = make_comparison(:a, :d)
            assert_equal 271, comp.max_color_distance.ceil
          end

          test "max_color_distance 1.0" do
            a_img = ChunkyPNG::Image.from_blob(File.binread("#{TEST_IMAGES_DIR}/a.png"))
            a_img[9, 6] += 0x010000

            comp = make_comparison(:a, :b)
            other_img_filename = comp.new_file_name
            a_img.save(other_img_filename)

            assert_equal 1, comp.max_color_distance
          end

          test "size a vs a_cropped" do
            comp = make_comparison(:a, :a_cropped)
            comp.different?
            assert_equal 4800, comp.difference_region_area_size
          end

          # Test Interface Contracts

          test "from_file loads image from path" do
            driver = ChunkyPNGDriver.new("#{Rails.root}/screenshot.png")
            assert driver.from_file("#{TEST_IMAGES_DIR}/a.png")
          end

          private

          def make_comparison(old_img, new_img, options = {})
            comp = ImageCompare.new(
              "#{Rails.root}/screenshot.png",
              nil,
              options.merge(driver: :chunky_png)
            )
            set_test_images(comp, old_img, new_img)
            comp
          end

          def sample_region
            [0, 0, 0, 0]
          end
        end
      end
    end
  end
end
