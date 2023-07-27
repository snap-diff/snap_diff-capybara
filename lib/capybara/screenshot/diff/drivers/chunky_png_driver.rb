# frozen_string_literal: true

require "chunky_png"

require "capybara/screenshot/diff/drivers/base_driver"

module Capybara
  module Screenshot
    module Diff
      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      module Drivers
        class ChunkyPNGDriver < BaseDriver
          include ChunkyPNG::Color

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

          def find_difference_region(comparison)
            DifferenceRegionFinder.new(comparison, self).perform
          end

          def crop(region, i)
            i.crop(*region.to_top_left_corner_coordinates)
          end

          def from_file(filename)
            ChunkyPNG::Image.from_file(filename.to_s)
          end

          def save_image_to(image, filename)
            image.save(filename)
          end

          def resize_image_to(image, new_width, new_height)
            image.resample_bilinear(new_width, new_height)
          end

          def load_image_files(old_file_name, file_name)
            [File.binread(old_file_name), File.binread(file_name)]
          end

          def draw_rectangles(images, region, (r, g, b), offset: 0)
            border_color = ChunkyPNG::Color.rgb(r, g, b)
            border_shadow = ChunkyPNG::Color.rgba(r, g, b, 100)

            images.map do |image|
              new_img = image.dup
              new_img.rect(region.left - offset, region.top - offset, region.right + offset, region.bottom + offset, border_color)
              new_img.rect(region.left, region.top, region.right, region.bottom, border_shadow)
              new_img
            end
          end

          def same_pixels?(comparison)
            comparison.new_image == comparison.base_image
          end

          private

          def _load_images(old_file, new_file)
            [ChunkyPNG::Image.from_blob(old_file), ChunkyPNG::Image.from_blob(new_file)]
          end

          class DifferenceRegionFinder
            attr_accessor :skip_area, :color_distance_limit, :shift_distance_limit

            def initialize(comparison, driver = nil)
              @comparison = comparison
              @driver = driver

              @color_distance_limit = comparison.options[:color_distance_limit]
              @shift_distance_limit = comparison.options[:shift_distance_limit]
              @skip_area = comparison.options[:skip_area]
            end

            def perform
              find_difference_region(@comparison)
            end

            def find_difference_region(comparison)
              new_image, base_image, = comparison.new_image, comparison.base_image

              meta = {}
              meta[:max_color_distance] = 0
              meta[:max_shift_distance] = 0 if shift_distance_limit

              region = find_top(base_image, new_image, cache: meta)
              region = if region.nil? || region[1].nil?
                nil
              else
                find_diff_rectangle(base_image, new_image, region, cache: meta)
              end

              result = Difference.new(region, meta, comparison)

              unless result.blank?
                meta[:max_color_distance] = meta[:max_color_distance].ceil(1) if meta[:max_color_distance]

                if comparison.options[:tolerance]
                  meta[:difference_level] = difference_level(nil, base_image, region)
                end
              end

              result
            end

            def difference_level(_diff_mask, base_image, region)
              image_area_size = @driver.image_area_size(base_image)
              return nil if image_area_size.zero?

              region.size.to_f / image_area_size
            end

            def find_diff_rectangle(org_img, new_img, area_coordinates, cache:)
              left, top, right, bottom = find_left_right_and_top(org_img, new_img, area_coordinates, cache: cache)
              bottom = find_bottom(org_img, new_img, left, right, bottom, cache: cache)

              Region.from_edge_coordinates(left, top, right, bottom)
            end

            def find_top(old_img, new_img, cache:)
              old_img.height.times do |y|
                old_img.width.times do |x|
                  return [x, y, x, y] unless same_color?(old_img, new_img, x, y, cache: cache)
                end
              end
              nil
            end

            def find_left_right_and_top(old_img, new_img, region, cache:)
              region = region.is_a?(Region) ? region.to_edge_coordinates : region

              left = region[0] || old_img.width - 1
              top = region[1]
              right = region[2] || 0
              bottom = region[3]

              old_img.height.times do |y|
                (0...left).find do |x|
                  next if same_color?(old_img, new_img, x, y, cache: cache)

                  top ||= y
                  bottom = y
                  left = x
                  right = x if x > right
                  x
                end
                (old_img.width - 1).step(right + 1, -1).find do |x|
                  unless same_color?(old_img, new_img, x, y, cache: cache)
                    bottom = y
                    right = x
                  end
                end
              end

              [left, top, right, bottom]
            end

            def find_bottom(old_img, new_img, left, right, bottom, cache:)
              if bottom
                (old_img.height - 1).step(bottom + 1, -1).find do |y|
                  (left..right).find do |x|
                    bottom = y unless same_color?(old_img, new_img, x, y, cache: cache)
                  end
                end
              end

              bottom
            end

            def same_color?(old_img, new_img, x, y, cache:)
              return true if skipped_region?(x, y)

              color_distance =
                color_distance_at(new_img, old_img, x, y, shift_distance_limit: @shift_distance_limit)

              if color_distance > cache[:max_color_distance]
                cache[:max_color_distance] = color_distance
              end

              color_matches = color_distance == 0 ||
                (!!@color_distance_limit && @color_distance_limit > 0 && color_distance <= @color_distance_limit)

              return color_matches if !@shift_distance_limit || cache[:max_shift_distance] == Float::INFINITY

              shift_distance = (color_matches && 0) ||
                shift_distance_at(new_img, old_img, x, y, color_distance_limit: @color_distance_limit)
              if shift_distance && (cache[:max_shift_distance].nil? || shift_distance > cache[:max_shift_distance])
                cache[:max_shift_distance] = shift_distance
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
          end
        end
      end
    end
  end
end
