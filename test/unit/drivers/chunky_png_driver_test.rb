# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/image_compare"
require "capybara/screenshot/diff/drivers/chunky_png_driver"

module Capybara
  module Screenshot
    module Diff
      module Drivers
        class ChunkyPNGDriverTest < ActiveSupport::TestCase
          include CapybaraScreenshotDiff::DSLStub

          class QuickEqualTest < self
            test "#quick_equal? returns true when comparing identical images" do
              comp = make_comparison(:a, :a)
              assert comp.quick_equal?
            end

            test "#quick_equal? respects color_distance_limit setting when images are similar" do
              comp = make_comparison(:a, :b, color_distance_limit: 224)
              assert comp.quick_equal?
            end
          end

          class DifferentTest < self
            test "#different? returns false when comparing identical images" do
              comp = make_comparison(:a, :a)
              assert_not comp.different?
            end

            test "#different? respects tolerance setting when images differ slightly" do
              comp = make_comparison(:a, :b, tolerance: 2)
              assert_not comp.different?
              assert comp.quick_equal?
            end

            test "#different? identifies differences and generates annotated comparison images" do
              comp = make_comparison(:a, :c)
              assert comp.different?
              assert_includes comp.error_message, "[11,3,48,20]"
              assert File.exist?(comp.base_image_path)
              assert File.exist?(comp.reporter.annotated_base_image_path)
              assert File.exist?(comp.reporter.annotated_image_path)

              assert_same_images("a-and-c.diff.png", comp.reporter.annotated_base_image_path)
              assert_same_images("c-and-a.diff.png", comp.reporter.annotated_image_path)
            end

            test "#different? skips generating annotated images for identical images" do
              comp = make_comparison(:c, :c)
              assert_not comp.different?

              assert comp.reporter.annotated_base_image_path
              assert comp.reporter.annotated_image_path

              assert_not File.exist?(comp.reporter.annotated_base_image_path)
              assert_not File.exist?(comp.reporter.annotated_image_path)
            end

            test "#different? detects single-pixel width differences between images" do
              comp = make_comparison(:a, :d)
              assert comp.different?
              assert_includes comp.error_message, "[9,6,9,13]"
            end

            test "#different? respects shift_distance_limit when within allowed threshold" do
              comp = make_comparison(:a, :b, shift_distance_limit: 11)
              assert comp.quick_equal?
              assert_not comp.different?
            end

            test "#different? enforces shift_distance_limit when beyond allowed threshold" do
              comp = make_comparison(:a, :b, shift_distance_limit: 9)
              assert comp.different?
              assert_includes comp.error_message, "11"
            end

            test "#different? detects when images have different dimensions" do
              comp = make_comparison(:a, :a_cropped)
              assert comp.different?
              assert_includes comp.error_message, "Dimensions have changed: "
              assert_includes comp.error_message, "80x60"
            end
          end

          class ColorDistanceTest < self
            test "#different? respects color_distance_limit when within allowed threshold" do
              comp = make_comparison(:a, :b, color_distance_limit: 223)
              assert_not comp.different?
            end

            test "#different? enforces color_distance_limit when beyond allowed threshold" do
              comp = make_comparison(:a, :b, color_distance_limit: 222)
              assert comp.different?
              assert_includes comp.error_message, "222.7"
            end

            test "#max_color_distance returns expected value for images with minor differences" do
              comp = make_comparison(:a, :b)
              assert_not comp.quick_equal?
              comp.different?
              assert_includes comp.error_message, "85"
            end

            test "#max_color_distance returns expected value for images with moderate differences" do
              comp = make_comparison(:a, :c)
              comp.different?
              assert_includes comp.error_message, "187.4"
            end

            test "#max_color_distance returns expected value for images with significant differences" do
              comp = make_comparison(:a, :d)
              comp.different?
              assert_includes comp.error_message, "269.1"
            end

            test "#max_color_distance detects minimal color differences between images" do
              a_img = ChunkyPNG::Image.from_blob(File.binread("#{TEST_IMAGES_DIR}/a.png"))
              a_img[9, 6] += 0x010000

              comp = make_comparison(:a, :b)
              other_img_filename = comp.image_path
              a_img.save(other_img_filename)

              comp.different?

              assert_includes comp.error_message, "1"
            end
          end

          class HelpersTest < self
            test "#from_file successfully loads an image from the specified path" do
              driver = ChunkyPNGDriver.new
              assert driver.from_file("#{TEST_IMAGES_DIR}/a.png")
            end
          end

          def make_comparison(old_img, new_img, options = {})
            snap = create_snapshot_for(old_img, new_img)
            ImageCompare.new(snap.path, snap.base_path, **options)
          end

          def sample_region
            [0, 0, 0, 0]
          end

          def load_test_image(driver)
            driver.from_file("#{TEST_IMAGES_DIR}/a.png")
          end
        end
      end
    end
  end
end
