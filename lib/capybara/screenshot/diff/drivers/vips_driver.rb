# frozen_string_literal: true

begin
  require "vips"
rescue LoadError => e
  warn 'Required ruby-vips gem is missing. Add `gem "ruby-vips"` to Gemfile' if e.message.include?("vips")
  raise
end

require_relative "./chunky_png_driver"

module Capybara
  module Screenshot
    module Diff
      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      module Drivers
        class VipsDriver
          attr_reader :new_file_name, :old_file_name, :options

          def initialize(new_file_name, old_file_name = nil, **options)
            @new_file_name = new_file_name
            @old_file_name = old_file_name || "#{new_file_name}~"

            @options = options || {}

            reset
          end

          # Resets the calculated data about the comparison with regard to the "new_image".
          # Data about the original image is kept.
          def reset
          end

          def shift_distance_equal?
            warn "[capybara-screenshot-diff] Instead of shift_distance_limit " \
                   "please use median_filter_window_size and color_distance_limit options"
            chunky_png_comparator.quick_equal?
          end

          def shift_distance_different?
            warn "[capybara-screenshot-diff] Instead of shift_distance_limit " \
                   "please use median_filter_window_size and color_distance_limit options"
            chunky_png_comparator.different?
          end

          def find_difference_region(new_image, old_image, color_distance_limit, _shift_distance_limit, _area_size_limit, fast_fail: false)
            diff_mask = VipsUtil.difference_mask(color_distance_limit, old_image, new_image)
            region = VipsUtil.difference_region_by(diff_mask)

            [region, diff_mask]
          end

          def size(region)
            return 0 unless region

            (region[2] - region[0]) * (region[3] - region[1])
          end

          def adds_error_details_to(_log)
          end

          # old private

          def inscribed?(dimensions, i)
            dimension(i) == dimensions || i.width < dimensions[0] || i.height < dimensions[1]
          end

          def crop(dimensions, i)
            i.crop(0, 0, *dimensions)
          end

          def filter_image_with_median(image, median_filter_window_size)
            image.median(median_filter_window_size)
          end

          def add_black_box(memo, region)
            memo.draw_rect([0, 0, 0, 0], *region, fill: true)
          end

          def chunky_png_comparator
            @chunky_png_comparator ||= ImageCompare.new(
              @new_file_name,
              @old_file_name,
              @options.merge(driver: :chunky_png, tolerance: nil, median_filter_window_size: nil)
            )
          end

          def difference_level(diff_mask, old_img, _region = nil)
            VipsUtil.difference_area_size_by(diff_mask).to_f / image_area_size(old_img)
          end

          def image_area_size(old_img)
            width_for(old_img) * height_for(old_img)
          end

          def height_for(image)
            image.height
          end

          def width_for(image)
            image.width
          end

          def save_image_to(image, filename)
            image.write_to_file(filename)
          end

          def resize_image_to(image, new_width, new_height)
            image.resize(1.* new_width / new_height)
          end

          def load_images(old_file_name, new_file_name, driver = self)
            [driver.from_file(old_file_name), driver.from_file(new_file_name)]
          end

          def from_file(filename)
            result = ::Vips::Image.new_from_file(filename)

            result = result.colourspace("srgb") if result.bands < 3
            result = result.bandjoin(255) if result.bands == 3

            result
          end

          def dimension_changed?(org_image, new_image)
            return false if dimension(org_image) == dimension(new_image)

            change_msg = [org_image, new_image].map { |i| "#{i.width}x#{i.height}" }.join(" => ")
            warn "Image size has changed for #{@new_file_name}: #{change_msg}"

            true
          end

          def dimension(image)
            [image.width, image.height]
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
              right = columns.width - columns.flip("horizontal").profile[1].min
              top = rows.profile[0].min
              bottom = rows.height - rows.flip("vertical").profile[0].min

              [left, top, right, bottom]
            end
          end
        end
      end
    end
  end
end
