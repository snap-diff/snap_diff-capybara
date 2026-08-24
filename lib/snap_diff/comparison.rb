# frozen_string_literal: true

require "pathname"
require "fileutils"

require "snap_diff/comparison_result"
require "snap_diff/drivers"
require "snap_diff/image_preprocessor"
require "snap_diff/removal"
require "snap_diff/reporters/default"

module SnapDiff
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
  class Comparison
    # Holds the two images (and their paths/options/driver) being compared
    # (ADR-008 step 5: ex-Capybara::Screenshot::Diff::Comparison struct).
    Images = Struct.new(:new_image, :base_image, :options, :driver, :new_image_path, :base_image_path) do
      def skip_area
        options[:skip_area]
      end
    end

    TOLERABLE_OPTIONS = [:tolerance, :color_distance_limit, :shift_distance_limit, :area_size_limit].freeze

    # Every key anything downstream of here actually reads -- capture
    # options included, because ScreenshotMatcher hands the same hash to the
    # screenshoter and only carves :crop / :stability_time_limit / :wait out
    # of the copy it passes on.
    #
    # Written out rather than derived from Config#default_options: that hash
    # is what the gem merges in, so deriving from it would make the check
    # agree with itself and validate nothing about the keys a USER adds.
    KNOWN_OPTIONS = %i[
      area_size_limit
      capybara_screenshot_options
      color_distance_limit
      crop
      delayed
      driver
      median_filter_window_size
      perceptual_threshold
      screenshot_format
      shift_distance_limit
      skip_area
      stability_time_limit
      tolerance
      wait
    ].freeze

    attr_reader :driver, :driver_options
    attr_reader :image_path, :base_image_path
    attr_reader :difference, :error_message

    def initialize(image_path, base_image_path, options = {})
      @image_path = Pathname.new(image_path)
      @base_image_path = Pathname.new(base_image_path)

      ensure_files_exist!

      @driver_options = options.freeze
      # THE no-silent-no-op check (ADR-010). Every option hash in the gem
      # reaches this constructor, so a key nothing reads is caught here
      # whichever entry point produced it. Frozen-but-unvalidated is how a
      # misspelt `tolerence:` bought a green suite that compared nothing.
      (options.keys - KNOWN_OPTIONS).each do |key|
        Removal.warn_once(:"unknown_option_#{key}", Removal.unknown_option(key))
      end
      # The per-comparison half of the shift_distance_limit removal (the
      # global half is Config#shift_distance_limit=). Presence is not enough:
      # config.default_options carries the key on EVERY comparison, nil for
      # everyone who never set it.
      if options[:shift_distance_limit]
        Removal.warn_once(:shift_distance_limit, Removal::SHIFT_DISTANCE_LIMIT_REMOVED)
      end
      @driver = Drivers.for(@driver_options)
      @without_tolerable_options = (driver_options.keys & TOLERABLE_OPTIONS).empty?
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
      return true if identical_files?

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
    # @see #analyze_difference
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

    def without_tolerable_options?
      @without_tolerable_options
    end

    def load_images_and_build_comparison(base_path, new_path, options)
      base_img, new_img = driver.load_images(base_path, new_path)
      Images.new(new_img, base_img, options, driver, new_path, base_path)
    end

    def image_preprocessor
      @image_preprocessor ||= ImagePreprocessor.new(driver, driver_options)
    end

    def find_difference(quick_mode: false)
      # Validate images exist
      return build_null_difference("missing_image") unless images_exist?

      # Step 1 of the layered strategy documented on this class: byte-identical
      # files cannot have different pixels. quick_equal? has always checked
      # this; the full path did not, and paid a decode of BOTH PNGs (11ms at
      # 1440x900, 25ms at 2880x1800) to reach the same "no difference" answer
      # on every screenshot that matches its baseline byte for byte.
      return build_null_difference if !quick_mode && identical_files?

      # Create comparison with preprocessed images
      comparison = load_comparison(base_image_path, image_path, driver_options)

      analyze_difference(comparison, quick_mode: quick_mode)
    end

    # Analyzes the comparison and determines if images are different.
    #
    # @param comparison [Comparison::Images] The comparison object containing images to analyze.
    # @param quick_mode [Boolean] When true, performs minimal checks and returns early.
    #   In quick mode, returns [is_equal, difference] where:
    #   - is_equal is true if images are considered equal
    #   - difference is a ComparisonResult object or nil
    #   When false, returns a ComparisonResult object directly.
    # @return [Array, ComparisonResult] Result format depends on quick_mode parameter.
    def analyze_difference(comparison, quick_mode: true)
      # Handle dimension differences
      unless driver.same_dimension?(comparison)
        result = ComparisonResult.build_null(comparison, comparison.base_image_path, comparison.new_image_path, {different_dimensions: true})
        return quick_mode ? [false, result] : result
      end

      # Handle identical pixels
      if driver.same_pixels?(comparison)
        result = ComparisonResult.build_null(comparison, comparison.base_image_path, comparison.new_image_path)
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
    # 3. Creating a Comparison::Images object that holds the image data
    #
    # @param base_path [String,Pathname] Path to the baseline/reference image
    # @param new_path [String,Pathname] Path to the new/candidate image
    # @param options [Hash] Comparison options including:
    #   - :crop [Array<Integer>] Optional crop area [x, y, width, height]
    #   - :skip_area [Array<Array>] Areas to exclude from comparison
    #   - :tolerance [Numeric] Color tolerance threshold
    # @return [Comparison::Images] Prepared comparison object ready for analysis
    # @raise [ArgumentError] If image files are invalid or unreadable
    def load_comparison(base_path, new_path, options)
      comparison = load_images_and_build_comparison(base_path, new_path, options)
      image_preprocessor.process_comparison(comparison)
    end

    def build_null_difference(failed_by = nil)
      comparison = Images.new(nil, nil, driver_options, driver, image_path, base_image_path).freeze
      ComparisonResult.build_null(comparison, base_image_path, image_path, failed_by)
    end

    # Check if both images exist
    def images_exist?
      base_image_path.exist? && image_path.exist?
    end

    # Are the two screenshots the same bytes? Sizes first: a stat each rules
    # out most pairs without reading either file.
    def identical_files?
      base_image_path.size == image_path.size && files_identical?(base_image_path, image_path)
    end

    # Check if files are identical by content
    def files_identical?(file1, file2)
      FileUtils.compare_file(file1, file2)
    rescue SystemCallError, IOError
      false
    end
  end
end
