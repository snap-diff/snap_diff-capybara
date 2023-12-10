# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      LOADED_DRIVERS = {}

      # Compare two image and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      class ImageCompare
        TOLERABLE_OPTIONS = [:tolerance, :color_distance_limit, :shift_distance_limit, :area_size_limit].freeze

        attr_reader :driver, :driver_options

        attr_reader :image_path, :base_image_path, :new_file_name, :old_file_name

        attr_reader :difference

        def initialize(image_path, base_image_path, options = {})
          @reporter = nil
          @error_message = nil

          @image_path = Pathname.new(image_path)

          @new_file_name = @image_path.to_s
          @annotated_image_path = @image_path.sub_ext(".diff.png")

          @base_image_path = Pathname.new(base_image_path)

          @old_file_name = @base_image_path.to_s
          @annotated_base_image_path = @base_image_path.sub_ext(".diff.png")

          @driver_options = options.dup

          @driver = Drivers.for(@driver_options)
        end

        # Compare the two image files and return `true` or `false` as quickly as possible.
        # Return falsely if the old file does not exist or the image dimensions do not match.
        def quick_equal?

          return false unless image_files_exist?
          # TODO: Confirm this change. There are screenshots with the same size, but there is a big difference
          return true if new_file_size == old_file_size

          comparison = load_and_process_images

          return false unless driver.same_dimension?(comparison)

          return true if driver.same_pixels?(comparison)

          # Could not make any difference to be tolerable, so skip and return as not equal
          return false if without_tolerable_options?

          @difference = driver.find_difference_region(comparison)
          @reporter = nil
          @error_message = nil

          !@difference.different?
        end

        # Compare the two image referenced by this object, and return `true` if they are different,
        # and `false` if they are the same.
        def different?
          @error_message = nil
          @reporter = nil

          @difference = find_difference unless processed?

          @error_message = report(@difference)

          @difference.different?
        end

        def image_files_exist?
          @base_image_path.exist? && @image_path.exist?
        end

        attr_reader :error_message

        def reporter(difference = @difference)
          @reporter ||= Capybara::Screenshot::Diff::Reporters::Default.new(difference || no_difference)
        end

        # TODO: Delete me
        def annotated_image_path
          return unless different?

          reporter.annotated_image_path
        end

        # TODO: Delete me
        def annotated_base_image_path
          return unless different?

          reporter.annotated_base_image_path
        end

        private

        def report(difference)
          reporter(difference).generate
        end

        def processed?
          !!@difference
        end

        def without_tolerable_options?
          (@driver_options.keys & TOLERABLE_OPTIONS).empty?
        end

        def find_difference
          raise ArgumentError, "There is no original (base) screenshot version to compare, located: #{@base_image_path}" unless @base_image_path.exist?
          raise ArgumentError, "There is no new screenshot version to compare, located: #{@image_path}" unless @image_path.exist?

          comparison = load_and_process_images

          unless driver.same_dimension?(comparison)
            return failed_difference(comparison, { different_dimensions: true })
          end

          if driver.same_pixels?(comparison)
            no_difference(comparison)
          else
            driver.find_difference_region(comparison)
          end
        end

        def failed_difference(comparison, failed_by)
          Difference.new(
            nil,
            { difference_level: nil, max_color_distance: 0 },
            comparison,
            failed_by
          )
        end

        def load_and_process_images
          images = driver.load_images(old_file_name, new_file_name)
          base_image, new_image = preprocess_images(images)
          Comparison.new(new_image, base_image, @driver_options, driver, image_path, base_image_path)
        end

        def skip_area
          @driver_options[:skip_area]
        end

        def median_filter_window_size
          @driver_options[:median_filter_window_size]
        end

        def dimensions
          @driver_options[:dimensions]
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
            result = blur_image_by(image, median_filter_window_size)
          end

          result
        end

        def blur_image_by(image, size)
          driver.filter_image_with_median(image, size)
        end

        def ignore_skipped_area(image)
          skip_area.reduce(image) { |memo, region| driver.add_black_box(memo, region) }
        end

        def old_file_size
          @old_file_size ||= image_files_exist? && File.size(@old_file_name)
        end

        def new_file_size
          File.size(@new_file_name)
        end

        def no_difference(comparison = nil)
          Difference.new(
            nil,
            { difference_level: nil, max_color_distance: 0 },
            comparison || Comparison.new(nil, nil, driver_options, driver, image_path, base_image_path)
          ).freeze
        end

      end

      class Comparison < Struct.new(:new_image, :base_image, :options, :driver, :new_image_path, :base_image_path)
      end
    end
  end
end
