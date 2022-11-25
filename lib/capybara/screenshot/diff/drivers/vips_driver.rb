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
          attr_reader :new_file_name, :old_file_name

          def initialize(new_file_name, old_file_name, _options = nil)
            @new_file_name = new_file_name
            @old_file_name = old_file_name

            reset
          end

          def skip_area=(_new_skip_area)
            # noop
          end

          # Resets the calculated data about the comparison with regard to the "new_image".
          # Data about the original image is kept.
          def reset
          end

          def shift_distance_equal?
            warn "[capybara-screenshot-diff] Instead of shift_distance_limit " \
                   "please use median_filter_window_size and color_distance_limit options" \
                   "or set explicit chunky_png driver"
            raise NotImplementedError
          end

          def shift_distance_different?
            warn "[capybara-screenshot-diff] Instead of shift_distance_limit " \
                   "please use median_filter_window_size and color_distance_limit options" \
                   "or set explicit chunky_png driver"
            raise NotImplementedError
          end

          def find_difference_region(new_image, old_image, color_distance_limit, _shift_distance_limit, _area_size_limit, fast_fail: false)
            diff_mask = VipsUtil.difference_mask(color_distance_limit, old_image, new_image)
            region = VipsUtil.difference_region_by(diff_mask)

            [region, diff_mask]
          end

          def adds_error_details_to(_log)
          end

          # old private

          def inscribed?(dimensions, i)
            dimension(i) == dimensions || i.width < dimensions[0] || i.height < dimensions[1]
          end

          def crop(region, i)
            result = i.crop(*region.to_top_left_corner_coordinates)

            # FIXME: Vips is caching operations, and if we ware going to read the same file, he will use cached version for this
            #       so after we cropped files and stored in the same file, the next load will recover old version instead of cropped
            #       Workaround to make vips works with cropped versions
            Vips.cache_set_max(0)
            Vips.cache_set_max(1000)

            result
          rescue Vips::Error => e
            warn(
              "[capybara-screenshot-diff] Crop has been failed for " \
              "{ region: #{region.to_top_left_corner_coordinates.inspect}, image: #{dimension(i).join('x')} }"
            )
            raise e
          end

          def filter_image_with_median(image, median_filter_window_size)
            image.median(median_filter_window_size)
          end

          def add_black_box(memo, region)
            memo.draw_rect([0, 0, 0, 0], *region.to_top_left_corner_coordinates, fill: true)
          end

          def difference_level(diff_mask, old_img, _region)
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

          PNG_EXTENSION = ".png"

          # Vips could not work with the same file. Per each process we require to create new file
          def save_image_to(image, filename)
            ::Dir::Tmpname.create([filename, PNG_EXTENSION]) do |tmp_image_filename|
              image.write_to_file(tmp_image_filename)
              FileUtils.mv(tmp_image_filename, filename)
            end
          end

          def resize_image_to(image, new_width, new_height)
            image.resize(new_width.to_f / new_height)
          end

          def load_images(old_file_name, new_file_name)
            [from_file(old_file_name), from_file(new_file_name)]
          end

          def from_file(filename)
            result = ::Vips::Image.new_from_file(filename)

            result = result.colourspace(:srgb) if result.bands < 3
            result = result.bandjoin(255) if result.bands == 3

            result
          end

          def dimension(image)
            [width_for(image), height_for(image)]
          end

          def draw_rectangles(images, region, rgba)
            images.map do |image|
              image.draw_rect(rgba, region.left - 1, region.top - 1, region.width + 2, region.height + 2)
            end
          end

          class VipsUtil
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
              columns, rows = diff_mask.bandor.project

              left = columns.profile[1].min
              right = columns.width - columns.flip(:horizontal).profile[1].min

              top = rows.profile[0].min
              bottom = rows.height - rows.flip(:vertical).profile[0].min

              return nil if right < left || bottom < top

              Region.from_edge_coordinates(left, top, right, bottom)
            end
          end
        end
      end
    end
  end
end
