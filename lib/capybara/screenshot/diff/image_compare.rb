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

        attr_reader :annotated_new_file_name, :annotated_old_file_name, :new_file_name, :old_file_name, :skip_area
        attr_accessor :shift_distance_limit, :area_size_limit, :color_distance_limit

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

        def skip_area=(new_skip_area)
          @skip_area = new_skip_area
          driver.skip_area = @skip_area
        end

        # Compare the two image files and return `true` or `false` as quickly as possible.
        # Return falsely if the old file does not exist or the image dimensions do not match.
        def quick_equal?
          return false unless old_file_exists?
          return true if new_file_size == old_file_size

          images = driver.load_images(@old_file_name, @new_file_name)
          old_image, new_image = preprocess_images(images, driver)

          return false if driver.dimension_changed?(old_image, new_image)

          self.difference_region, meta = driver.find_difference_region(
            new_image,
            old_image,
            @color_distance_limit,
            @shift_distance_limit,
            @area_size_limit,
            fast_fail: true
          )

          return true if difference_region_area_size.zero? || difference_region_empty?(new_image, difference_region)
          return true if @area_size_limit && difference_region_area_size <= @area_size_limit
          return true if @tolerance && @tolerance >= driver.difference_level(meta, old_image, difference_region)
          # TODO: Remove this or find similar solution for vips
          return true if @shift_distance_limit && driver.shift_distance_equal?

          false
        end

        # Compare the two images referenced by this object, and return `true` if they are different,
        # and `false` if they are the same.
        def different?
          return false unless old_file_exists?

          images = driver.load_images(@old_file_name, @new_file_name)
          old_image, new_image = preprocess_images(images, driver)

          if driver.dimension_changed?(old_image, new_image)
            self.difference_region = Region.from_edge_coordinates(
              0,
              0,
              [driver.width_for(old_image), driver.width_for(new_image)].min,
              [driver.height_for(old_image), driver.height_for(new_image)].min
            )

            return different(*images)
          end

          self.difference_region, meta = driver.find_difference_region(
            new_image,
            old_image,
            @color_distance_limit,
            @shift_distance_limit,
            @area_size_limit
          )

          return not_different if difference_region_area_size.zero? || difference_region_empty?(old_image, difference_region)
          return not_different if @area_size_limit && difference_region_area_size <= @area_size_limit
          return not_different if @tolerance && @tolerance > driver.difference_level(meta, old_image, difference_region)
          # TODO: Remove this or find similar solution for vips
          return not_different if @shift_distance_limit && !driver.shift_distance_different?

          different(*images)
        end

        def clean_tmp_files
          FileUtils.cp @old_file_name, @new_file_name if old_file_exists?
          File.delete(@old_file_name) if old_file_exists?
          File.delete(@annotated_old_file_name) if File.exist?(@annotated_old_file_name)
          File.delete(@annotated_new_file_name) if File.exist?(@annotated_new_file_name)
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

        NEW_LINE = "\n"

        def error_message
          result = {
            area_size: difference_region_area_size,
            region: difference_coordinates
          }

          driver.adds_error_details_to(result)

          [
            "(#{result.to_json})",
            new_file_name,
            annotated_old_file_name,
            annotated_new_file_name
          ].join(NEW_LINE)
        end

        def difference_coordinates
          difference_region&.to_edge_coordinates
        end

        def difference_region_area_size
          return 0 unless difference_region

          difference_region.size
        end

        private

        attr_accessor :difference_region

        def different(old_image, new_image)
          annotate_and_save([old_image, new_image], difference_region)
          true
        end

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

        def difference_region_empty?(new_image, region)
          region.nil? ||
            (
              region.height == height_for(new_image) &&
                region.width == width_for(new_image) &&
                region.x.zero? &&
                region.y.zero?
            )
        end

        def annotate_and_save(images, region)
          annotated_images = annotate_difference(images, region)
          annotated_images = annotate_skip_areas(annotated_images, @skip_area) if @skip_area

          save(*annotated_images, @annotated_old_file_name, @annotated_new_file_name)
        end

        DIFF_COLOR = [255, 0, 0, 255].freeze

        def annotate_difference(images, region)
          driver.draw_rectangles(images, region, DIFF_COLOR)
        end

        SKIP_COLOR = [255, 192, 0, 255].freeze

        def annotate_skip_areas(annotated_images, skip_areas)
          skip_areas.reduce(annotated_images) do |annotated_images, region|
            driver.draw_rectangles(annotated_images, region, SKIP_COLOR)
          end
        end
      end
    end
  end
end
