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

      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      #
      # This class implements a layered optimization strategy for image comparison:
      # 1. Early file-based checks:
      #    - First checks if both images exist
      #    - Then checks file sizes (identical size is necessary but not sufficient for equality)
      #    - For same-sized files, performs a byte-by-byte comparison for exact matching
      # 2. Only if needed, loads and preprocesses images for comparison
      # 3. Delegates detailed analysis to DifferenceFinder
      #
      # This approach significantly improves performance by avoiding expensive image
      # processing operations when simpler file-based checks can determine the result.
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

        # Compare the two image files and return `true` or `false` as quickly as possible.
        # Return falsely if the old file does not exist or the image dimensions do not match.
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

        # Compare the two image referenced by this object, and return `true` if they are different,
        # and `false` if they are the same.
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

        # Load and preprocess images for comparison
        # @param base_path [String,Pathname] Path to the base image
        # @param new_path [String,Pathname] Path to the new image
        # @param options [Hash] Options for the comparison
        # @return [Comparison] the comparison object
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
