# frozen_string_literal: true

require "chunky_png"

module Capybara
  module Screenshot
    module Diff
      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      module Drivers
        class ChunkyPNGDriver
          include ChunkyPNG::Color

          attr_reader :new_file_name, :old_file_name
          attr_accessor :skip_area, :color_distance_limit, :shift_distance_limit

          def initialize(new_file_name, old_file_name, options = {})
            @new_file_name = new_file_name
            @old_file_name = old_file_name

            @color_distance_limit = options[:color_distance_limit]
            @shift_distance_limit = options[:shift_distance_limit]
            @skip_area = options[:skip_area]

            reset
          end

          # Resets the calculated data about the comparison with regard to the "new_image".
          # Data about the original image is kept.
          def reset
            @max_color_distance = @color_distance_limit ? 0 : nil
            @max_shift_distance = @shift_distance_limit ? 0 : nil
          end

          def load_images(old_file_name, new_file_name)
            old_bytes, new_bytes = load_image_files(old_file_name, new_file_name)

            _load_images(old_bytes, new_bytes)
          end

          def filter_image_with_median(_image)
            raise NotImplementedError
          end

          def add_black_box(image, _region)
            image
          end

          def difference_level(_diff_mask, old_img, region)
            region.size.to_f / image_area_size(old_img)
          end

          def image_area_size(old_img)
            width_for(old_img) * height_for(old_img)
          end

          def shift_distance_equal?
            # Stub
            false
          end

          def shift_distance_different?
            # Stub
            true
          end

          def find_difference_region(new_image, old_image, color_distance_limit, shift_distance_limit, area_size_limit, fast_fail: false)
            return nil, nil if new_image.pixels == old_image.pixels

            if fast_fail && !(color_distance_limit || shift_distance_limit || area_size_limit)
              return build_region_for_whole_image(new_image), nil
            end

            region = find_top(old_image, new_image)
            region = if region.nil? || region[1].nil?
              nil
            else
              find_diff_rectangle(old_image, new_image, region)
            end

            [region, nil]
          end

          def height_for(image)
            image.height
          end

          def width_for(image)
            image.width
          end

          def max_color_distance
            calculate_metrics unless @max_color_distance
            @max_color_distance
          end

          def max_shift_distance
            calculate_metrics unless @max_shift_distance || !@shift_distance_limit
            @max_shift_distance
          end

          def adds_error_details_to(log)
            max_color_distance = self.max_color_distance.ceil(1)
            max_shift_distance = self.max_shift_distance

            log[:max_color_distance] = max_color_distance
            log.merge!(max_shift_distance: max_shift_distance) if max_shift_distance
          end

          def crop(region, i)
            i.crop(*region.to_top_left_corner_coordinates)
          end

          def from_file(filename)
            ChunkyPNG::Image.from_file(filename)
          end

          # private

          def calculate_metrics
            old_file, new_file = load_image_files(@old_file_name, @new_file_name)

            if old_file == new_file
              @max_color_distance = 0
              @max_shift_distance = 0
              return
            end

            old_image, new_image = _load_images(old_file, new_file)
            calculate_max_color_distance(new_image, old_image)
            calculate_max_shift_limit(new_image, old_image) if @shift_distance_limit
          end

          def calculate_max_color_distance(new_image, old_image)
            pixel_pairs = old_image.pixels.zip(new_image.pixels)
            @max_color_distance = pixel_pairs.inject(0) { |max, (p1, p2)|
              next max unless p1 && p2

              d = ChunkyPNG::Color.euclidean_distance_rgba(p1, p2)
              [max, d].max
            }
          end

          def calculate_max_shift_limit(new_img, old_img)
            (0...new_img.width).each do |x|
              (0...new_img.height).each do |y|
                shift_distance =
                  shift_distance_at(new_img, old_img, x, y, color_distance_limit: @color_distance_limit)
                if shift_distance && (@max_shift_distance.nil? || shift_distance > @max_shift_distance)
                  @max_shift_distance = shift_distance
                  return if @max_shift_distance == Float::INFINITY # rubocop: disable Lint/NonLocalExitFromIterator
                end
              end
            end
          end

          def save_image_to(image, filename)
            image.save(filename)
          end

          def resize_image_to(image, new_width, new_height)
            image.resample_bilinear(new_width, new_height)
          end

          def load_image_files(old_file_name, file_name)
            old_file = File.binread(old_file_name)
            new_file = File.binread(file_name)
            [old_file, new_file]
          end

          def draw_rectangles(images, region, (r, g, b))
            border_color = ChunkyPNG::Color.rgb(r, g, b)
            border_shadow = ChunkyPNG::Color.rgba(r, g, b, 100)

            images.map do |image|
              new_img = image.dup
              new_img.rect(region.left - 1, region.top - 1, region.right + 1, region.bottom + 1, border_color)
              new_img.rect(region.left, region.top, region.right, region.bottom, border_shadow)
              new_img
            end
          end

          def dimension(image)
            [width_for(image), height_for(image)]
          end

          private

          def build_region_for_whole_image(new_image)
            Region.from_edge_coordinates(0, 0, width_for(new_image), height_for(new_image))
          end

          def find_diff_rectangle(org_img, new_img, area_coordinates)
            left, top, right, bottom = find_left_right_and_top(org_img, new_img, area_coordinates)
            bottom = find_bottom(org_img, new_img, left, right, bottom)

            Region.from_edge_coordinates(left, top, right, bottom)
          end

          def find_top(old_img, new_img)
            old_img.height.times do |y|
              old_img.width.times do |x|
                return [x, y, x, y] unless same_color?(old_img, new_img, x, y)
              end
            end
            nil
          end

          def find_left_right_and_top(old_img, new_img, region)
            region = region.is_a?(Region) ? region.to_edge_coordinates : region

            left = region[0] || old_img.width - 1
            top = region[1]
            right = region[2] || 0
            bottom = region[3]

            old_img.height.times do |y|
              (0...left).find do |x|
                next if same_color?(old_img, new_img, x, y)

                top ||= y
                bottom = y
                left = x
                right = x if x > right
                x
              end
              (old_img.width - 1).step(right + 1, -1).find do |x|
                unless same_color?(old_img, new_img, x, y)
                  bottom = y
                  right = x
                end
              end
            end

            [left, top, right, bottom]
          end

          def find_bottom(old_img, new_img, left, right, bottom)
            if bottom
              (old_img.height - 1).step(bottom + 1, -1).find do |y|
                (left..right).find do |x|
                  bottom = y unless same_color?(old_img, new_img, x, y)
                end
              end
            end

            bottom
          end

          def same_color?(old_img, new_img, x, y)
            return true if skipped_region?(x, y)

            color_distance =
              color_distance_at(new_img, old_img, x, y, shift_distance_limit: @shift_distance_limit)

            if !@max_color_distance || color_distance > @max_color_distance
              @max_color_distance = color_distance
            end

            color_matches = color_distance == 0 ||
              (!!@color_distance_limit && @color_distance_limit > 0 && color_distance <= @color_distance_limit)

            return color_matches if !@shift_distance_limit || @max_shift_distance == Float::INFINITY

            shift_distance = (color_matches && 0) ||
              shift_distance_at(new_img, old_img, x, y, color_distance_limit: @color_distance_limit)
            if shift_distance && (@max_shift_distance.nil? || shift_distance > @max_shift_distance)
              @max_shift_distance = shift_distance
            end

            color_matches
          end

          def skipped_region?(x, y)
            return false unless @skip_area

            @skip_area.any? { |region| region.cover?(x, y) }
          end

          def color_distance_at(new_img, old_img, x, y, shift_distance_limit:)
            org_color = old_img[x, y]
            if shift_distance_limit
              start_x = [0, x - shift_distance_limit].max
              end_x = [x + shift_distance_limit, new_img.width - 1].min
              xs = (start_x..end_x).to_a
              start_y = [0, y - shift_distance_limit].max
              end_y = [y + shift_distance_limit, new_img.height - 1].min
              ys = (start_y..end_y).to_a
              new_pixels = xs.product(ys)

              distances = new_pixels.map do |dx, dy|
                ChunkyPNG::Color.euclidean_distance_rgba(org_color, new_img[dx, dy])
              end
              distances.min
            else
              ChunkyPNG::Color.euclidean_distance_rgba(org_color, new_img[x, y])
            end
          end

          def shift_distance_at(new_img, old_img, x, y, color_distance_limit:)
            org_color = old_img[x, y]
            shift_distance = 0
            loop do
              bounds_breached = 0
              top_row = y - shift_distance
              if top_row >= 0 # top
                ([0, x - shift_distance].max..[x + shift_distance, new_img.width - 1].min).each do |dx|
                  if color_matches(new_img, org_color, dx, top_row, color_distance_limit)
                    return shift_distance
                  end
                end
              else
                bounds_breached += 1
              end
              if shift_distance > 0
                if (x - shift_distance) >= 0 # left
                  ([0, top_row + 1].max..[y + shift_distance, new_img.height - 2].min)
                    .each do |dy|
                    if color_matches(new_img, org_color, x - shift_distance, dy, color_distance_limit)
                      return shift_distance
                    end
                  end
                else
                  bounds_breached += 1
                end
                if (y + shift_distance) < new_img.height # bottom
                  ([0, x - shift_distance].max..[x + shift_distance, new_img.width - 1].min).each do |dx|
                    if color_matches(new_img, org_color, dx, y + shift_distance, color_distance_limit)
                      return shift_distance
                    end
                  end
                else
                  bounds_breached += 1
                end
                if (x + shift_distance) < new_img.width # right
                  ([0, top_row + 1].max..[y + shift_distance, new_img.height - 2].min)
                    .each do |dy|
                    if color_matches(new_img, org_color, x + shift_distance, dy, color_distance_limit)
                      return shift_distance
                    end
                  end
                else
                  bounds_breached += 1
                end
              end
              break if bounds_breached == 4

              shift_distance += 1
            end
            Float::INFINITY
          end

          def color_matches(new_img, org_color, x, y, color_distance_limit)
            new_color = new_img[x, y]
            return new_color == org_color unless color_distance_limit

            color_distance = ChunkyPNG::Color.euclidean_distance_rgba(org_color, new_color)
            color_distance <= color_distance_limit
          end

          def _load_images(old_file, new_file)
            [ChunkyPNG::Image.from_blob(old_file), ChunkyPNG::Image.from_blob(new_file)]
          end
        end
      end
    end
  end
end
