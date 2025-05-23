# frozen_string_literal: true

require "pathname"
require "fileutils"

require "capybara/screenshot/diff/comparison"
require "capybara/screenshot/diff/comparison_loader"
require "capybara/screenshot/diff/image_preprocessor"
require "capybara/screenshot/diff/difference_finder"
require "capybara/screenshot/diff/reporters/default"

module Capybara
  module Screenshot
    module Diff
      LOADED_DRIVERS = {}

      # Handles comparison of two images with a focus on performance and accuracy.
      #
      # This class implements a multi-layered optimization strategy for image comparison:
      #
      # 1. Early File-based Checks (Fastest):
      #    - Verifies both images exist (raises ArgumentError if not)
      #    - Compares file sizes (different sizes → different images)
      #    - Performs byte-by-byte comparison for identical files (exact match)
      #
      # 2. Quick Comparison (Fast):
      #    - Compares image dimensions (different dimensions → different images)
      #    - Performs pixel-by-pixel comparison if dimensions match
      #
      # 3. Detailed Analysis (Slower):
      #    - Only performed if quick comparison finds differences
      #    - Handles anti-aliasing, color tolerance, and shift detection
      #    - Respects skip_area and other comparison parameters
      #
      # This layered approach ensures optimal performance by:
      # - Using the fastest possible method for early rejection
      # - Only performing expensive operations when absolutely necessary
      # - Maintaining high accuracy for complex comparisons
      class ImageCompare
        attr_reader :driver, :driver_options
        attr_reader :image_path, :base_image_path
        attr_reader :difference, :error_message

        def initialize(image_path, base_image_path, options = {})
          @image_path = Pathname.new(image_path)
          @base_image_path = Pathname.new(base_image_path)

          ensure_files_exist!

          @driver_options = options.dup
          @driver = Drivers.for(@driver_options)
        end

        # Performs a quick comparison of two image files.
        #
        # This method is optimized for speed and will return as soon as a difference is found.
        # It's used for fast rejection before performing more expensive comparisons.
        #
        # @return [Boolean]
        #   - `true` if images are exactly identical (byte-for-byte match)
        #   - `false` if images are different or if a quick difference is detected
        #
        # @note This method will raise ArgumentError if either image file is missing.
        def quick_equal?
          ensure_files_exist!

          # Quick file size check - if sizes are equal, perform a simple file comparison
          if base_image_path.size == image_path.size
            # If we have identical files (same size and content), we can return true immediately
            # without more expensive comparison
            return true if files_identical?(base_image_path, image_path)
          end

          result, difference = find_difference(quick_mode: true)
          self.difference = difference
          result
        end

        def ensure_files_exist!
          raise ArgumentError, "There is no original (base) screenshot located at #{@base_image_path}" unless @base_image_path.exist?
          raise ArgumentError, "There is no new screenshot located at #{@image_path}" unless @image_path.exist?
        end

        # Determines if the images are different according to the comparison rules.
        #
        # This method performs a full comparison if not already done, including any
        # configured tolerances for color differences and shift distances.
        #
        # @return [Boolean]
        #   - `true` if the images are different beyond configured tolerances
        #   - `false` if the images are considered identical
        #
        # @see #processed
        # @see DifferenceFinder
        def different?
          processed.difference.different?
        end

        def dimensions_changed?
          difference.failed_by&.[](:different_dimensions)
        end

        def reporter
          @reporter ||= build_reporter
        end

        def processed?
          !!difference
        end

        def processed
          self.difference = find_difference(quick_mode: false) unless processed?
          @error_message ||= reporter.generate
          self
        end

        private

        def difference_finder
          @difference_finder ||= DifferenceFinder.new(driver, driver_options)
        end

        def comparison_loader
          @comparison_loader ||= ComparisonLoader.new(driver)
        end

        def image_preprocessor
          @image_preprocessor ||= ImagePreprocessor.new(driver, driver_options)
        end

        def find_difference(quick_mode: false)
          # Validate images exist
          return build_null_difference("missing_image") unless images_exist?

          # Create comparison with preprocessed images
          comparison = load_comparison(base_image_path, image_path, driver_options)

          # Use difference finder to analyze the comparison
          difference_finder.call(comparison, quick_mode: quick_mode)
        end

        def difference=(new_difference)
          @error_message = nil
          @reporter = nil
          @difference = new_difference
        end

        def build_reporter
          current_difference = difference || build_null_difference
          Reporters::Default.new(current_difference)
        end

        # Loads and preprocesses images for detailed comparison.
        #
        # This method is responsible for:
        # 1. Loading both images using the configured driver
        # 2. Applying any necessary preprocessing (cropping, normalization)
        # 3. Creating a Comparison object that holds the image data
        #
        # @param base_path [String,Pathname] Path to the baseline/reference image
        # @param new_path [String,Pathname] Path to the new/candidate image
        # @param options [Hash] Comparison options including:
        #   - :crop [Array<Integer>] Optional crop area [x, y, width, height]
        #   - :skip_area [Array<Array>] Areas to exclude from comparison
        #   - :tolerance [Numeric] Color tolerance threshold
        # @return [Comparison] Prepared comparison object ready for analysis
        # @raise [ArgumentError] If image files are invalid or unreadable
        def load_comparison(base_path, new_path, options)
          comparison = comparison_loader.call(base_path, new_path, options)
          image_preprocessor.process_comparison(comparison)
        end

        def build_null_difference(failed_by = nil, comparison = nil)
          Difference.build_null(comparison || build_null_comparison, base_image_path, image_path, failed_by)
        end

        def build_null_comparison
          Comparison.new(nil, nil, driver_options, driver, image_path, base_image_path).freeze
        end

        # Check if both images exist
        def images_exist?
          base_image_path.exist? && image_path.exist?
        end

        # Check if files are identical by content
        def files_identical?(file1, file2)
          # Compare file contents
          FileUtils.identical?(file1, file2)
        rescue
          # If there's any error reading the files, they're not identical
          false
        end
      end
    end
  end
end
