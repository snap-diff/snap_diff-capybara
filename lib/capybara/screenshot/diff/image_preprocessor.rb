# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      # Handles image preprocessing operations (skip_area and median filtering)
      #
      # This class applies preprocessing filters to images before comparison,
      # such as masking specific regions (skip_area) or applying noise reduction.
      # It's designed to work with either direct image objects or with options.
      class ImagePreprocessor
        attr_reader :driver, :options

        def initialize(driver, options = {})
          @driver = driver
          @options = options
        end

        # Process a comparison object directly
        # This allows reusing the comparison's existing options
        # @param [Comparison] comparison the comparison object
        # @return [Comparison] the comparison object
        def process_comparison(comparison)
          # Process both images
          comparison.base_image = process_image(comparison.base_image, comparison.base_image_path)
          comparison.new_image = process_image(comparison.new_image, comparison.new_image_path)

          comparison
        end

        def call(images)
          images.map { |image| process_image(image, nil) }
        end

        private

        def process_image(image, path)
          result = image
          result = apply_skip_area(result) if skip_area
          result = apply_median_filter(result, path) if median_filter_window_size
          result
        end

        def apply_skip_area(image)
          skip_area.reduce(image) do |result, region|
            driver.add_black_box(result, region)
          end
        end

        def apply_median_filter(image, path)
          if driver.supports?(:filter_image_with_median)
            driver.filter_image_with_median(image, median_filter_window_size)
          else
            warn_about_skipped_median_filter(path)
            image
          end
        end

        def warn_about_skipped_median_filter(path)
          warn(
            "[capybara-screenshot-diff] Median filter has been skipped for #{path} " \
            "because it is not supported by #{driver.class}"
          )
        end

        def skip_area
          options[:skip_area]
        end

        def median_filter_window_size
          options[:median_filter_window_size]
        end
      end
    end
  end
end
