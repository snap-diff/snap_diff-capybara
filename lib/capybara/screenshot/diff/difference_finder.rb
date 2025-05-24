# frozen_string_literal: true

require "capybara/screenshot/diff/comparison"
require "capybara/screenshot/diff/difference"

module Capybara
  module Screenshot
    module Diff
      # Analyzes image differences with configurable tolerance levels.
      #
      # This class implements the core comparison logic for detecting visual differences
      # between images while accounting for various tolerances and optimizations.
      #
      # The comparison process follows these steps:
      # 1. Dimension Check (Fastest)
      #    - Compares image dimensions first for quick rejection
      #    - Different dimensions always indicate a difference
      #
      # 2. Pixel Equality Check (Fast)
      #    - Performs bitwise comparison if dimensions match
      #    - Returns immediately if images are exactly identical
      #
      # 3. Tolerant Comparison (Slower)
      #    - Only runs if quick checks don't determine equality
      #    - Respects configured tolerances for color and shift differences
      #    - Can ignore specific regions (skip_area)
      #    - Considers anti-aliasing and sub-pixel rendering differences
      #
      # The class is designed to be stateless and thread-safe, with all configuration
      # passed in through the constructor.
      class DifferenceFinder
        TOLERABLE_OPTIONS = [:tolerance, :color_distance_limit, :shift_distance_limit, :area_size_limit].freeze

        attr_reader :driver, :options

        # Creates a new DifferenceFinder instance.
        #
        # @param driver [Drivers::Base] The image processing driver to use.
        #   Must implement the driver interface expected by DifferenceFinder.
        # @param options [Hash] Configuration options for the comparison:
        #   @option options [Numeric] :tolerance (0.001) Color tolerance threshold (0.0-1.0).
        #   @option options [Numeric] :color_distance_limit Maximum allowed color distance.
        #   @option options [Numeric] :shift_distance_limit Maximum allowed shift distance.
        #   @option options [Numeric] :area_size_limit Maximum allowed difference area size.
        #   @option options [Array<Array>] :skip_area Regions to exclude from comparison.
        def initialize(driver, options)
          @driver = driver
          @options = options
        end

        # Analyzes the comparison and determines if images are different.
        #
        # @param comparison [Comparison] The comparison object containing images to analyze.
        # @param quick_mode [Boolean] When true, performs minimal checks and returns early.
        #   In quick mode, returns [is_equal, difference] where:
        #   - is_equal is true if images are considered equal
        #   - difference is a Difference object or nil
        #   When false, returns a Difference object directly.
        # @return [Array, Difference] Result format depends on quick_mode parameter.
        # @raise [ArgumentError] If the comparison object is invalid.
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
