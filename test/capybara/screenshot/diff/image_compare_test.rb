require 'test_helper'

module Capybara
  module Screenshot
    module Diff
      class ImageCompareTest < ActionDispatch::IntegrationTest
        test 'compare class method' do
          assert ImageCompare.compare("#{TEST_IMAGES_DIR}/b.png")
        end

        test 'it can be instantiated' do
          assert ImageCompare.new('images/b.png')
        end

        test 'it can be instantiated with dimensions' do
          assert ImageCompare.new('images/b.png', dimensions: [80, 80])
        end

        test 'compare then dimensions and cleanup' do
          comp = make_comparison(:a, :c)
          assert comp.different?
          assert_equal [11, 3, 48, 20], comp.dimensions
          assert File.exist?(comp.old_file_name)
          assert File.exist?(comp.annotated_old_file_name)
          assert File.exist?(comp.annotated_new_file_name)
          comp = make_comparison(:c, :c)
          assert !comp.different?
          assert !File.exist?(comp.old_file_name)
          assert !File.exist?(comp.annotated_old_file_name)
          assert !File.exist?(comp.annotated_new_file_name)
        end

        test 'compare of 1 pixel wide diff' do
          comp = make_comparison(:a, :d)
          assert comp.different?
          assert_equal [9, 6, 9, 13], comp.dimensions
        end

        test 'compare with color_distance_limit above difference' do
          comp = make_comparison(:a, :b, color_distance_limit: 223)
          assert !comp.different?
          assert_equal 223, comp.max_color_distance.ceil
        end

        test 'compare with color_distance_limit below difference' do
          comp = make_comparison(:a, :b, color_distance_limit: 222)
          assert comp.different?
          assert_equal 223, comp.max_color_distance.ceil
        end

        test 'quick_equal' do
          comp = make_comparison(:a, :b)
          assert !comp.quick_equal?
          assert_equal 10, comp.max_color_distance.ceil
        end

        test 'quick_equal with color distance limit' do
          comp = make_comparison(:a, :b, color_distance_limit: 222)
          assert comp.different?
          assert_equal 223, comp.max_color_distance.ceil
        end

        test 'max_color_distance a vs b' do
          comp = make_comparison(:a, :b)
          assert_equal 223, comp.max_color_distance.ceil
        end

        test 'max_color_distance a vs c' do
          comp = make_comparison(:a, :c)
          assert_equal 318, comp.max_color_distance.ceil
        end

        test 'max_color_distance a vs d' do
          comp = make_comparison(:a, :d)
          assert_equal 271, comp.max_color_distance.ceil
        end

        test 'max_color_distance 1.0' do
          begin
            a_img = ChunkyPNG::Image.from_blob(File.binread("#{TEST_IMAGES_DIR}/a.png"))
            a_img[9, 6] += 0x010000

            comp = make_comparison(:a, :b)
            other_img_filename = comp.new_file_name
            a_img.save(other_img_filename)

            assert_equal 1, comp.max_color_distance
          end
        end

        private

        def make_comparison(old_img, new_img, color_distance_limit: nil)
          comp = ImageCompare.new("#{Rails.root}/screenshot.png", color_distance_limit: color_distance_limit)
          set_test_images(comp, old_img, new_img)
          comp
        end

        def set_test_images(comp, old_img, new_img)
          FileUtils.cp "#{TEST_IMAGES_DIR}/#{old_img}.png", comp.old_file_name
          FileUtils.cp "#{TEST_IMAGES_DIR}/#{new_img}.png", comp.new_file_name
        end
      end
    end
  end
end
