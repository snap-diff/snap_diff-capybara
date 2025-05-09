# frozen_string_literal: true

require "capybara/screenshot/diff/comparison"
require "capybara/screenshot/diff/difference"

module Capybara
  module Screenshot
    module Diff
      # Responsible for finding differences between images
      #
      # This class follows the Single Responsibility Principle by focusing solely on analyzing
      # image comparisons to identify differences. It's part of a layered comparison approach:
      #
      # 1. Image existence and basic file checks happen in ImageCompare (early returns)
      # 2. DifferenceFinder performs the actual comparison analysis when needed:
      #    - First checks dimensions (quick, fails early if different)
      #    - Then checks pixel equality (moderate cost)
      #    - Finally performs detailed region analysis (most expensive)
      #
      # By separating these concerns, we can optimize performance by avoiding unnecessary
      # processing steps when simpler checks determine the result.
      class DifferenceFinder
        TOLERABLE_OPTIONS = [:tolerance, :color_distance_limit, :shift_distance_limit, :area_size_limit].freeze

        attr_reader :driver, :options

        # Initialize a new DifferenceFinder
        #
        # @param driver [Drivers::Base] The image driver to use
        # @param options [Hash] Options for controlling the comparison
        def initialize(driver, options)
          @driver = driver
          @options = options
        end

        # Finds a difference in a comparison
        #
        # @param comparison [Comparison] The comparison object to analyze
        # @param quick_mode [Boolean] If true, performs a quick equality check and returns early
        # @return [Array, Difference] Either [is_equal, difference] or a Difference object depending on mode
        def call(comparison, quick_mode: true)
          # Process the comparison and return result

          # Handle dimension differences
          unless driver.same_dimension?(comparison)
            result = build_null_difference(comparison, comparison.base_image_path, comparison.new_image_path, {different_dimensions: true})
            return quick_mode ? [false, result] : result
          end

          # Handle identical pixels
          if driver.same_pixels?(comparison)
            result = build_null_difference(comparison, comparison.base_image_path, comparison.new_image_path)
            return quick_mode ? [true, result] : result
          end

          # Handle early return for non-tolerable options
          if quick_mode && without_tolerable_options?
            return [false, nil]
          end

          # Process difference region
          region = driver.find_difference_region(comparison)

          # Only create a proper difference object if we've completed the comparison
          quick_mode ? [!region.different?, region] : region
        end

        private

        def without_tolerable_options?
          (options.keys & TOLERABLE_OPTIONS).empty?
        end

        # Build a no-difference result that represents identical images
        def build_null_difference(comparison, base_path, new_path, failed_by = nil)
          Difference.build_null(comparison, base_path, new_path, failed_by)
        end
      end
    end
  end
end
