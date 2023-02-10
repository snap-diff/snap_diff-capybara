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

        attr_reader :annotated_image_path, :annotated_base_image_path,
          :image_path, :base_image_path,
          :new_file_name, :old_file_name

        def initialize(image_path, base_image_path, options = {})
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
          @error_message = nil
          return false unless image_files_exist?
          # TODO: Confirm this change. There are screenshots with the same size, but there is a big difference
          return true if new_file_size == old_file_size

          comparison = load_and_process_images

          unless driver.same_dimension?(comparison)
            @error_message = build_error_for_different_dimensions(comparison)
            return false
          end

          return true if driver.same_pixels?(comparison)

          # Could not make any difference to be tolerable, so skip and return as not equal
          return false if without_tolerable_options?

          @difference = driver.find_difference_region(comparison)
          return true unless @difference.different?

          @error_message = @difference.inspect
          false
        end

        # Compare the two image referenced by this object, and return `true` if they are different,
        # and `false` if they are the same.
        def different?
          @error_message = nil

          @error_message = _different?

          clean_tmp_files unless @error_message

          !@error_message.nil?
        end

        def build_error_for_different_dimensions(comparison)
          change_msg = [comparison.base_image, comparison.new_image]
            .map { |i| driver.dimension(i).join("x") }
            .join(" => ")

          "Screenshot dimension has been changed for #{@new_file_name}: #{change_msg}"
        end

        def clean_tmp_files
          @annotated_base_image_path.unlink if @annotated_base_image_path.exist?
          @annotated_image_path.unlink if @annotated_image_path.exist?
        end

        def save(image, image_path)
          driver.save_image_to(image, image_path.to_s)
        end

        def image_files_exist?
          @base_image_path.exist? && @image_path.exist?
        end

        NEW_LINE = "\n"

        attr_reader :error_message

        private

        def without_tolerable_options?
          (@driver_options.keys & TOLERABLE_OPTIONS).empty?
        end

        def _different?
          raise "There are no screenshots to compare!" unless image_files_exist?

          comparison = load_and_process_images

          unless driver.same_dimension?(comparison)
            return build_error_for_different_dimensions(comparison)
          end

          return not_different if driver.same_pixels?(comparison)

          @difference = driver.find_difference_region(comparison)
          return not_different unless @difference.different?

          different(@difference)
        end

        def load_and_process_images
          images = driver.load_images(old_file_name, new_file_name)
          base_image, new_image = preprocess_images(images)
          Comparison.new(new_image, base_image, @driver_options)
        end

        def build_error_message(difference)
          [
            "(#{difference.inspect})",
            new_file_name,
            annotated_base_image_path.to_path,
            annotated_image_path.to_path
          ].join(NEW_LINE)
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

        def different(difference)
          annotate_and_save_images(difference)
          build_error_message(difference)
        end

        def preprocess_images(images)
          images.map { preprocess_image(_1) }
        end

        def preprocess_image(image)
          result = image

          # FIXME: How can we access to this method from public interface? Is this not documented feature?
          if dimensions && driver.inscribed?(dimensions, result)
            result = driver.crop(dimensions, result)
          end

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

        def not_different
          nil
        end

        def annotate_and_save_images(difference)
          annotate_and_save_image(difference, difference.comparison.new_image, @annotated_image_path)
          annotate_and_save_image(difference, difference.comparison.base_image, @annotated_base_image_path)
        end

        def annotate_and_save_image(difference, image, image_path)
          image = annotate_difference(image, difference.region)
          image = annotate_skip_areas(image, difference.skip_area) if difference.skip_area
          save(image, image_path.to_path)
        end

        DIFF_COLOR = [255, 0, 0, 255].freeze

        def annotate_difference(image, region)
          driver.draw_rectangles(Array[image], region, DIFF_COLOR, offset: 1).first
        end

        SKIP_COLOR = [255, 192, 0, 255].freeze

        def annotate_skip_areas(image, skip_areas)
          skip_areas.reduce(image) do |memo, region|
            driver.draw_rectangles(Array[memo], region, SKIP_COLOR).first
          end
        end
      end

      class Comparison < Struct.new(:new_image, :base_image, :options)
      end
    end
  end
end
