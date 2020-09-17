# frozen_string_literal: true

begin
  require 'vips'
rescue LoadError => e
  warn 'Required ruby-vips gem is missing. Add `gem "ruby-vips"` to Gemfile' if e.message.include?('vips')
  raise
end

require_relative './chunky_png_driver'

module Capybara
  module Screenshot
    module Diff
      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      module Drivers
        class VipsDriver
          attr_reader :annotated_new_file_name, :annotated_old_file_name, :area_size_limit,
                      :color_distance_limit, :new_file_name, :old_file_name, :shift_distance_limit,
                      :skip_area, :tolerance

          def initialize(new_file_name, old_file_name = nil, **options)
            @new_file_name = new_file_name
            @old_file_name = old_file_name || "#{new_file_name}~"
            @annotated_old_file_name = "#{new_file_name.chomp('.png')}.committed.png"
            @annotated_new_file_name = "#{new_file_name.chomp('.png')}.latest.png"

            @color_distance_limit = options[:color_distance_limit] || 0
            @area_size_limit = options[:area_size_limit]
            @shift_distance_limit = options[:shift_distance_limit]
            @dimensions = options[:dimensions]
            @skip_area = options[:skip_area]
            @tolerance = options[:tolerance]
            @median_filter_window_size = options[:median_filter_window_size]

            reset
          end

          # Resets the calculated data about the comparison with regard to the "new_image".
          # Data about the original image is kept.
          def reset
            self.difference_region = nil
          end

          # Compare the two image files and return `true` or `false` as quickly as possible.
          # Return falsish if the old file does not exist or the image dimensions do not match.
          def quick_equal?
            return nil unless old_file_exists?

            old_image, new_image = preprocess_images vips_load_images(@old_file_name, @new_file_name)

            return false if dimension_changed?(old_image, new_image)

            diff_mask = VipsUtil.difference_mask(@color_distance_limit, old_image, new_image)
            self.difference_region = VipsUtil.difference_region_by(diff_mask)

            return true if difference_region_empty?(new_image)

            return true if @area_size_limit && size <= @area_size_limit

            return true if @tolerance && @tolerance >= difference_level(diff_mask, old_image)

            # TODO: Remove this or find similar solution for vips
            if @shift_distance_limit
              warn '[capybara-screenshot-diff] Instead of shift_distance_limit ' \
                   'please use median_filter_window_size and color_distance_limit options'
              return true if chunky_png_driver.quick_equal?
            end

            false
          end

          # Compare the two images referenced by this object, and return `true` if they are different,
          # and `false` if they are the same.
          # Return `nil` if the old file does not exist or if the image dimensions do not match.
          def different?
            return nil unless old_file_exists?

            images = vips_load_images(@old_file_name, @new_file_name)

            old_img, new_img = preprocess_images(images)

            if dimension_changed?(old_img, new_img)
              save(new_img, old_img)

              self.difference_region = 0, 0, width_for(old_img), height_for(old_img)

              return true
            end

            diff_mask = VipsUtil.difference_mask(@color_distance_limit, old_img, new_img)
            self.difference_region = VipsUtil.difference_region_by(diff_mask)

            return not_different if difference_region_empty?(old_img)
            return not_different if @area_size_limit && size <= @area_size_limit
            return not_different if @tolerance && @tolerance > difference_level(diff_mask, old_img)

            # TODO: Remove this or find similar solution for vips
            if @shift_distance_limit
              warn '[capybara-screenshot-diff] Instead of shift_distance_limit ' \
                   'please use median_filter_window_size and color_distance_limit options'
              return not_different unless chunky_png_driver.different?
            end

            annotate_and_save(images)

            true
          end

          def old_file_exists?
            @old_file_name && File.exist?(@old_file_name)
          end

          def dimensions
            difference_region
          end

          def size
            return 0 unless dimensions

            (@right - @left) * (@bottom - @top)
          end

          def error_message
            "(area: #{size}px #{dimensions})\n" \
            "#{new_file_name}\n#{annotated_old_file_name}\n" \
            "#{annotated_new_file_name}"
          end

          private

          def difference_region
            return nil unless @left || @top || @right || @bottom

            [@left, @top, @right, @bottom]
          end

          def difference_region=(region)
            @left, @top, @right, @bottom = region
          end

          def chunky_png_driver
            @chunky_png_driver ||= ChunkyPNGDriver.new(
              @new_file_name,
              @old_file_name,
              dimensions: @dimensions,
              color_distance_limit: @color_distance_limit,
              area_size_limit: @area_size_limit,
              shift_distance_limit: @shift_distance_limit,
              skip_area: @skip_area
            )
          end

          def difference_region_empty?(old_img)
            difference_region.nil? ||
              (@top == height_for(old_img) && @left == width_for(old_img) && @right.zero? && @bottom.zero?)
          end

          def preprocess_images(images)
            # TODO: Run preprocesses for new files only
            crop_images(images, @dimensions) if @dimensions

            old_img = preprocess_image(images.first)
            new_img = preprocess_image(images.last)

            [old_img, new_img]
          end

          def preprocess_image(image)
            result = @median_filter_window_size ? image.median(@median_filter_window_size) : image

            if @skip_area
              result = @skip_area.reduce(result) do |memo, region|
                memo.draw_rect([0, 0, 0, 0], *region, fill: true)
              end
            end

            result
          end

          def difference_level(diff_mask, old_img)
            VipsUtil.difference_area_size_by(diff_mask).to_f / image_area_size(old_img)
          end

          def image_area_size(old_img)
            width_for(old_img) * height_for(old_img)
          end

          def equal_by_pixels(new_img, old_img)
            old_img.to_a == new_img.to_a
          end

          def height_for(image)
            image.height
          end

          def width_for(image)
            image.width
          end

          def annotate_and_save(images)
            annotated_old_img, annotated_new_img = draw_rectangles(images, *difference_region)

            save(annotated_new_img, annotated_old_img)
          end

          def save(annotated_new_img, annotated_old_img)
            annotated_new_img.write_to_file(@annotated_new_file_name)
            annotated_old_img.write_to_file(@annotated_old_file_name)
          end

          def pixels(old_image)
            old_image.to_a
          end

          def not_different
            clean_tmp_files
            false
          end

          def clean_tmp_files
            FileUtils.cp @old_file_name, @new_file_name if old_file_exists?
            File.delete(@old_file_name) if old_file_exists?
            File.delete(@annotated_old_file_name) if File.exist?(@annotated_old_file_name)
            File.delete(@annotated_new_file_name) if File.exist?(@annotated_new_file_name)
          end

          def vips_load_images(old_file_name, new_file_name)
            [from_file(old_file_name), from_file(new_file_name)]
          end

          def from_file(old_file_name)
            result = ::Vips::Image.new_from_file(old_file_name)

            result = result.colourspace('srgb') if result.bands < 3
            result = result.bandjoin(255) if result.bands == 3

            result
          end

          def dimension_changed?(org_image, new_image)
            return unless dimension(org_image) != dimension(new_image)

            change_msg = [org_image, new_image].map { |i| "#{i.width}x#{i.height}" }.join(' => ')
            warn "Image size has changed for #{@new_file_name}: #{change_msg}"

            true
          end

          def dimension(image)
            [image.width, image.height]
          end

          def crop_images(images, dimensions)
            images.map! do |i|
              if dimension(i) == dimensions || i.width < dimensions[0] || i.height < dimensions[1]
                i
              else
                i.crop(0, 0, *dimensions)
              end
            end
          end

          RED_INK = [255, 0, 0, 255].freeze

          def draw_rectangles(images, left, top, right, bottom)
            images.map do |image|
              image.draw_rect(RED_INK, left - 1, top - 1, right - left + 2, bottom - top + 2)
            end
          end

          class VipsUtil
            def self.difference(old_image, new_image, color_distance: 0)
              diff_mask = difference_mask(color_distance, new_image, old_image)
              difference_region_by(diff_mask)
            end

            def self.difference_area(old_image, new_image, color_distance: 0)
              difference_mask = difference_mask(color_distance, new_image, old_image)
              difference_area_size_by(difference_mask)
            end

            def self.difference_area_size_by(difference_mask)
              diff_mask = difference_mask == 0
              diff_mask.hist_find.to_a[0][0].max
            end

            def self.difference_mask(color_distance, old_image, new_image)
              (new_image - old_image).abs > color_distance
            end

            def self.difference_region_by(diff_mask)
              columns, rows = diff_mask.project

              left = columns.profile[1].min
              right = columns.width - columns.flip('horizontal').profile[1].min
              top = rows.profile[0].min
              bottom = rows.height - rows.flip('vertical').profile[0].min

              [left, top, right, bottom]
            end
          end
        end
      end
    end
  end
end
