# frozen_string_literal: true

begin
  require "vips"
rescue LoadError => e
  raise 'Required ruby-vips gem is missing. Add `gem "ruby-vips"` to Gemfile' if e.message.match?(/vips/i)
  raise
end

require "snap_diff/driver"
require "snap_diff/drivers"
require "snap_diff/comparison_result"

module SnapDiff
  module Drivers
    class VipsDriver
      include SnapDiff::Driver

      def find_difference_region(comparison)
        new_image, base_image, options = comparison.new_image, comparison.base_image, comparison.options

        diff_mask = if options[:perceptual_threshold]
          self.class.perceptual_difference_mask(base_image, new_image, options[:perceptual_threshold])
        else
          self.class.difference_mask(base_image, new_image, options[:color_distance_limit])
        end
        region = self.class.difference_region_by(diff_mask)
        # TODO: schedule research when we got this case for VIPs
        # region = nil if region && region_covers_entire_image?(region, base_image)

        result = ComparisonResult.new(region, {}, comparison)

        unless result.blank?
          result.meta[:difference_level] = difference_level(diff_mask, base_image) if comparison.options[:tolerance]
          result.meta[:diff_mask] = diff_mask
        end

        result
      end

      def crop(region, i)
        i.crop(*region.to_top_left_corner_coordinates)
      rescue Vips::Error => e
        warn(
          "[capybara-screenshot-diff] Crop has been failed for " \
            "{ region: #{region.to_top_left_corner_coordinates.inspect}, image: #{dimension(i).join("x")} }"
        )
        raise e
      end

      def filter_image_with_median(image, median_filter_window_size)
        image.median(median_filter_window_size)
      end

      def add_black_box(memo, region)
        return memo unless region

        memo.draw_rect([0, 0, 0, 0], *region.to_top_left_corner_coordinates, fill: true)
      end

      def difference_level(diff_mask, old_img, _region = nil)
        self.class.difference_area_size_by(diff_mask).to_f / image_area_size(old_img)
      end

      MAX_FILENAME_LENGTH = 200

      # Vips could not work with the same file. Per each process we require to create new file
      def save_image_to(image, filename)
        # Dir::Tmpname will happily produce tempfile names that are too long for most unix filesystems,
        # which leads to "unix error: File name too long". Apply a limit to avoid this.
        limited_filename = filename.to_s[-MAX_FILENAME_LENGTH..] || filename.to_s
        ::Dir::Tmpname.create([limited_filename, PNG_EXTENSION]) do |tmp_image_filename|
          image.write_to_file(tmp_image_filename)
          FileUtils.mv(tmp_image_filename, filename)
        end
      end

      def resize_image_to(image, new_width, new_height)
        image.resize(new_width.to_f / image.width, vscale: new_height.to_f / image.height)
      end

      def load_images(old_file_name, new_file_name)
        [from_file(old_file_name), from_file(new_file_name)]
      end

      def from_file(filename)
        result = ::Vips::Image.new_from_file(filename.to_s)

        result = result.colourspace(:srgb) if result.bands < 3
        result = result.bandjoin(255) if result.bands == 3

        result
      end

      def draw_rectangles(images, region, rgba, offset: 0)
        images.map do |image|
          image.draw_rect(rgba, region.left - offset, region.top - offset, region.width + (offset * 2), region.height + (offset * 2))
        end
      end

      def same_pixels?(comparison)
        (comparison.new_image == comparison.base_image).min == 255
      end

      def merge(new_image, base_image)
        base_image.composite2(new_image, :over)
      end

      def highlight_mask(diff_mask, merged_image, color: CapybaraScreenshotDiff::RED_RGBA)
        diff_mask.ifthenelse(color, merged_image * 0.75)
      end

      private

      class << self
        def difference_area(old_image, new_image, color_distance: 0)
          mask = difference_mask(new_image, old_image, color_distance)
          difference_area_size_by(mask)
        end

        def difference_area_size_by(difference_mask)
          diff_mask = difference_mask == 0
          diff_mask.hist_find.to_a[0][0].max
        end

        def difference_mask(base_image, new_image, color_distance = nil)
          result = (new_image - base_image).abs
          color_distance ? result > color_distance : result
        end

        def perceptual_difference_mask(base_image, new_image, threshold = 2.0)
          color_diff = perceptual_color_diff(base_image, new_image) > threshold
          alpha_diff = alpha_channel_diff(base_image, new_image)
          alpha_diff ? (color_diff | alpha_diff) : color_diff
        end

        def perceptual_color_diff(base_image, new_image)
          base_rgb = (base_image.bands > 3) ? base_image.extract_band(0, n: 3) : base_image
          new_rgb = (new_image.bands > 3) ? new_image.extract_band(0, n: 3) : new_image
          base_lab = base_rgb.colourspace(:lab)
          new_lab = new_rgb.colourspace(:lab)
          base_lab.dE00(new_lab)
        rescue Vips::Error
          base_lab.dE76(new_lab)
        end

        def alpha_channel_diff(base_image, new_image)
          return unless base_image.bands > 3 && new_image.bands > 3

          (base_image.extract_band(3) - new_image.extract_band(3)).abs > 0
        end

        def difference_region_by(diff_mask)
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
