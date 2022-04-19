# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      LOADED_DRIVERS = {}

      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      class ImageCompare < SimpleDelegator
        TMP_FILE_SUFFIX = "~"

        attr_reader :driver, :driver_options

        attr_reader :annotated_new_file_name, :annotated_old_file_name, :area_size_limit,
          :color_distance_limit, :new_file_name, :old_file_name, :shift_distance_limit,
          :skip_area

        def initialize(new_file_name, old_file_name = nil, options = {})
          options = old_file_name if old_file_name.is_a?(Hash)

          @new_file_name = new_file_name
          @old_file_name = old_file_name || "#{new_file_name}#{ImageCompare::TMP_FILE_SUFFIX}"
          @annotated_old_file_name = "#{new_file_name.chomp(".png")}.committed.png"
          @annotated_new_file_name = "#{new_file_name.chomp(".png")}.latest.png"

          @driver_options = options

          @color_distance_limit = options[:color_distance_limit] || 0
          @area_size_limit = options[:area_size_limit]
          @shift_distance_limit = options[:shift_distance_limit]
          @dimensions = options[:dimensions]
          @skip_area = options[:skip_area]
          @tolerance = options[:tolerance]
          @median_filter_window_size = options[:median_filter_window_size]

          driver_klass = find_driver_class_for(@driver_options.fetch(:driver, :chunky_png))
          @driver = driver_klass.new(@new_file_name, @old_file_name, **@driver_options)

          super(@driver)
        end

        # Compare the two image files and return `true` or `false` as quickly as possible.
        # Return falsish if the old file does not exist or the image dimensions do not match.
        def quick_equal?
          return false unless old_file_exists?
          return true if new_file_size == old_file_size

          # old_bytes, new_bytes = load_image_files(@old_file_name, @new_file_name)
          # return true if old_bytes == new_bytes

          images = driver.load_images(@old_file_name, @new_file_name)
          old_image, new_image = preprocess_images(images, driver)

          return false if driver.dimension_changed?(old_image, new_image)

          region, meta = driver.find_difference_region(
            new_image,
            old_image,
            @color_distance_limit,
            @shift_distance_limit,
            @area_size_limit,
            fast_fail: true
          )

          self.difference_region = region

          return true if difference_region_empty?(new_image, region)

          return true if @area_size_limit && driver.size(region) <= @area_size_limit

          return true if @tolerance && @tolerance >= driver.difference_level(meta, old_image, region)

          # TODO: Remove this or find similar solution for vips
          return true if @shift_distance_limit && driver.shift_distance_equal?

          false
        end

        # Compare the two images referenced by this object, and return `true` if they are different,
        # and `false` if they are the same.
        # Return `nil` if the old file does not exist or if the image dimensions do not match.
        def different?
          return nil unless old_file_exists?

          images = driver.load_images(@old_file_name, @new_file_name)

          old_image, new_image = preprocess_images(images, driver)

          if driver.dimension_changed?(old_image, new_image)
            save(new_image, old_image, @annotated_new_file_name, @annotated_old_file_name)

            self.difference_region = 0, 0, driver.width_for(old_image), driver.height_for(old_image)

            return true
          end

          region, meta = driver.find_difference_region(
            new_image,
            old_image,
            @color_distance_limit,
            @shift_distance_limit,
            @area_size_limit
          )
          self.difference_region = region

          return not_different if difference_region_empty?(old_image, region)
          return not_different if @area_size_limit && driver.size(region) <= @area_size_limit
          return not_different if @tolerance && @tolerance > driver.difference_level(meta, old_image, region)

          # TODO: Remove this or find similar solution for vips
          return not_different if @shift_distance_limit && !driver.shift_distance_different?

          annotate_and_save(images, region)

          true
        end

        def clean_tmp_files
          FileUtils.cp @old_file_name, @new_file_name if old_file_exists?
          File.delete(@old_file_name) if old_file_exists?
          File.delete(@annotated_old_file_name) if File.exist?(@annotated_old_file_name)
          File.delete(@annotated_new_file_name) if File.exist?(@annotated_new_file_name)
        end

        DIFF_COLOR = [255, 0, 0, 255].freeze
        SKIP_COLOR = [255, 192, 0, 255].freeze

        def annotate_and_save(images, region = difference_region)
          annotated_images = driver.draw_rectangles(images, region, DIFF_COLOR)
          @skip_area.to_a.flatten.each_slice(4) do |region|
            annotated_images = driver.draw_rectangles(annotated_images, region, SKIP_COLOR)
          end
          save(*annotated_images, @annotated_old_file_name, @annotated_new_file_name)
        end

        def save(old_img, new_img, annotated_old_file_name, annotated_new_file_name)
          driver.save_image_to(old_img, annotated_old_file_name)
          driver.save_image_to(new_img, annotated_new_file_name)
        end

        def old_file_exists?
          @old_file_name && File.exist?(@old_file_name)
        end

        def reset
          self.difference_region = nil
          driver.reset
        end

        def error_message
          result = {
            area_size: driver.size(difference_region),
            region: difference_region
          }

          driver.adds_error_details_to(result)

          ["(#{result.to_json})", new_file_name, annotated_old_file_name, annotated_new_file_name].join("\n")
        end

        def difference_region
          return nil unless @left || @top || @right || @bottom

          [@left, @top, @right, @bottom]
        end

        private

        def find_driver_class_for(driver)
          driver = AVAILABLE_DRIVERS.first if driver == :auto

          LOADED_DRIVERS[driver] ||=
            case driver
            when :chunky_png
              require "capybara/screenshot/diff/drivers/chunky_png_driver"
              Drivers::ChunkyPNGDriver
            when :vips
              require "capybara/screenshot/diff/drivers/vips_driver"
              Drivers::VipsDriver
            else
              fail "Wrong adapter #{driver.inspect}. Available adapters: #{AVAILABLE_DRIVERS.inspect}"
            end
        end

        def old_file_size
          @old_file_size ||= old_file_exists? && File.size(@old_file_name)
        end

        def new_file_size
          File.size(@new_file_name)
        end

        def not_different
          clean_tmp_files
          false
        end

        def load_images(old_file_name, new_file_name, driver = self)
          [driver.from_file(old_file_name), driver.from_file(new_file_name)]
        end

        def preprocess_images(images, driver = self)
          old_img = preprocess_image(images.first, driver)
          new_img = preprocess_image(images.last, driver)

          [old_img, new_img]
        end

        def preprocess_image(image, driver = self)
          result = image

          if @dimensions && driver.inscribed?(@dimensions, result)
            result = driver.crop(@dimensions, result)
          end

          if @median_filter_window_size
            result = driver.filter_image_with_median(image, @median_filter_window_size)
          end

          if @skip_area
            result = @skip_area.reduce(result) { |image, region| driver.add_black_box(image, region) }
          end

          result
        end

        def difference_region=(region)
          @left, @top, @right, @bottom = region
        end

        def difference_region_empty?(new_image, region)
          region.nil? ||
            (
              region[1] == height_for(new_image) &&
                region[0] == width_for(new_image) &&
                region[2].zero? &&
                region[3].zero?
            )
        end
      end
    end
  end
end
