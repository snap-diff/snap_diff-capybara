# frozen_string_literal: true

require "capybara/screenshot/diff/comparison"

module Capybara
  module Screenshot
    module Diff
      LOADED_DRIVERS = {}

      # Compare two image and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      class ImageCompare
        TOLERABLE_OPTIONS = [:tolerance, :color_distance_limit, :shift_distance_limit, :area_size_limit].freeze

        attr_reader :driver, :driver_options
        attr_reader :image_path, :base_image_path
        attr_reader :difference, :error_message

        def initialize(image_path, base_image_path, options = {})
          @image_path = Pathname.new(image_path)
          @base_image_path = Pathname.new(base_image_path)

          @driver_options = options.dup

          @driver = Drivers.for(@driver_options)
        end

        # Compare the two image files and return `true` or `false` as quickly as possible.
        # Return falsely if the old file does not exist or the image dimensions do not match.
        def quick_equal?
          require_images_exists!

          # NOTE: This is very fuzzy logic, but so far it's helps to support current performance.
          return true if new_file_size == old_file_size

          comparison = load_and_process_images

          unless driver.same_dimension?(comparison)
            self.difference = build_failed_difference(comparison, {different_dimensions: true})
            return false
          end

          if driver.same_pixels?(comparison)
            self.difference = build_no_difference(comparison)
            return true
          end

          # NOTE: Could not make any difference to be tolerable, so skip and return as not equal.
          return false if without_tolerable_options?

          self.difference = driver.find_difference_region(comparison)

          !difference.different?
        end

        # Compare the two image referenced by this object, and return `true` if they are different,
        # and `false` if they are the same.
        def different?
          processed.difference.different?
        end

        def reporter
          @reporter ||= begin
            current_difference = difference || build_no_difference(nil)
            Capybara::Screenshot::Diff::Reporters::Default.new(current_difference)
          end
        end

        def processed?
          !!difference
        end

        def processed
          self.difference = find_difference unless processed?
          @error_message ||= reporter.generate
          self
        end

        private

        def find_difference
          require_images_exists!

          comparison = load_and_process_images

          unless driver.same_dimension?(comparison)
            return build_failed_difference(comparison, {different_dimensions: true})
          end

          if driver.same_pixels?(comparison)
            build_no_difference(comparison)
          else
            driver.find_difference_region(comparison)
          end
        end

        def require_images_exists!
          raise ArgumentError, "There is no original (base) screenshot version to compare, located: #{base_image_path}" unless base_image_path.exist?
          raise ArgumentError, "There is no new screenshot version to compare, located: #{image_path}" unless image_path.exist?
        end

        def difference=(new_difference)
          @error_message = nil
          @reporter = nil
          @difference = new_difference
        end

        def image_files_exist?
          @base_image_path.exist? && @image_path.exist?
        end

        def without_tolerable_options?
          (@driver_options.keys & TOLERABLE_OPTIONS).empty?
        end

        def build_failed_difference(comparison, failed_by)
          Difference.new(
            nil,
            {difference_level: nil, max_color_distance: 0},
            comparison,
            failed_by
          )
        end

        def load_and_process_images
          images = driver.load_images(base_image_path, image_path)
          base_image, new_image = preprocess_images(images)
          Comparison.new(new_image, base_image, @driver_options, driver, image_path, base_image_path)
        end

        def skip_area
          @driver_options[:skip_area]
        end

        def median_filter_window_size
          @driver_options[:median_filter_window_size]
        end

        def preprocess_images(images)
          images.map { |image| preprocess_image(image) }
        end

        def preprocess_image(image)
          result = image

          if skip_area
            result = ignore_skipped_area(result)
          end

          if median_filter_window_size
            if driver.is_a?(Drivers::VipsDriver)
              result = blur_image_by(image, median_filter_window_size)
            else
              warn(
                "[capybara-screenshot-diff] Median filter has been skipped for #{image_path} " \
                  "because it is not supported by #{driver.class.name}"
              )
            end
          end

          result
        end

        def blur_image_by(image, size)
          driver.filter_image_with_median(image, size)
        end

        def ignore_skipped_area(image)
          skip_area&.reduce(image) { |memo, region| driver.add_black_box(memo, region) }
        end

        def old_file_size
          base_image_path.size
        end

        def new_file_size
          image_path.size
        end

        def build_no_difference(comparison = nil)
          Difference.new(
            nil,
            {difference_level: nil, max_color_distance: 0},
            comparison || build_comparison
          ).freeze
        end

        def build_comparison
          Capybara::Screenshot::Diff::Comparison.new(nil, nil, driver_options, driver, image_path, base_image_path).freeze
        end
      end
    end
  end
end
