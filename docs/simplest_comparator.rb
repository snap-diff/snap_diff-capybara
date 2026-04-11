# frozen_string_literal: true

# Prerequisite: You must have the `ruby-vips` gem installed and libvips on your system OS.
# gem install ruby-vips
require 'vips'

module VisualRegression
  class Comparator
    # Evaluates two images for visual regressions using a high-performance hybrid approach.
    #
    # @param baseline_path [String] Path to the original (baseline) image
    # @param test_path [String] Path to the new image being tested
    # @param options [Hash] Configuration for tolerances and masking
    # @option options [Array<Array>] :masks A list of [x, y, w, h] coordinates to ignore (e.g., [[0,0,100,50]])
    # @option options [Float] :size_tolerance Allowed file size difference ratio (default 0.05 / 5%)
    # @option options [Float] :color_tolerance Perceptual color diff threshold DE2000 (default 2.0)
    # @option options [Float] :pixel_tolerance Allowed ratio of mismatched pixels (default 0.001 / 0.1%)
    # @return [Hash] A hash containing the :match boolean and a :reason string
    def self.compare(baseline_path, test_path, options = {})
      masks       = options[:masks] || []
      size_tol    = options.fetch(:size_tolerance, 0.05)
      color_tol   = options.fetch(:color_tolerance, 2.0)
      pixel_tol   = options.fetch(:pixel_tolerance, 0.001)

      # =======================================================================
      # STEP 1: File Size Check (Instant Early Rejection)
      # =======================================================================
      base_size = File.size(baseline_path).to_f
      test_size = File.size(test_path).to_f

      # Avoid division by zero on empty files
      return { match: false, reason: "Baseline file is empty." } if base_size.zero?

      size_diff_ratio = (base_size - test_size).abs / base_size

      # If sizes are perfectly identical, they are highly likely the exact same file/render.
      # However, to be completely safe against dynamic data coincidentally matching byte size,
      # we still proceed. We ONLY reject if the difference is drastic.
      if size_diff_ratio > size_tol
        return {
          match: false,
          reason: "Fast Rejection: File size difference (#{(size_diff_ratio * 100).round(2)}%) exceeds #{size_tol * 100}% tolerance."
        }
      end

      # =======================================================================
      # STEP 2 & 3 SETUP: Load images into Libvips
      # `access: :sequential` tells VIPS to stream the image top-to-bottom,
      # which drastically reduces memory usage and speeds up processing.
      # =======================================================================
      begin
        base_img = Vips::Image.new_from_file(baseline_path, access: :sequential)
        test_img = Vips::Image.new_from_file(test_path, access: :sequential)
      rescue Vips::Error => e
        return { match: false, reason: "Image load error: #{e.message}" }
      end

      if base_img.width != test_img.width || base_img.height != test_img.height
        return { match: false, reason: "Dimensions mismatch: #{base_img.width}x#{base_img.height} vs #{test_img.width}x#{test_img.height}" }
      end

      # =======================================================================
      # STEP 2: Block Masking (Handle Dynamic Data)
      # Draw solid black rectangles over areas we know are noisy (ads, dates).
      # =======================================================================
      masks.each do |(x, y, w, h)|
        # format: draw_rect([R, G, B], x, y, width, height, fill: true)
        base_img = base_img.draw_rect([0, 0, 0], x, y, w, h, fill: true)
        test_img = test_img.draw_rect([0, 0, 0], x, y, w, h, fill: true)
      end

      # =======================================================================
      # STEP 3: Color Distance & Thresholding (Handle Anti-Aliasing)
      # =======================================================================
      # Ensure both images are in the standard sRGB colourspace before diffing
      base_img = base_img.colourspace(:srgb) unless base_img.interpretation == :srgb
      test_img = test_img.colourspace(:srgb) unless test_img.interpretation == :srgb

      # Calculate the perceptual color distance.
      # DE2000 (dE00) is a formula that mimics human vision. A value < 2.0 is generally
      # imperceptible to the human eye, neatly eating up tiny anti-aliasing artifacts.
      begin
        diff = base_img.dE00(test_img)
      rescue Vips::Error
        # Fallback to dE76 if you are using a very old version of libvips
        diff = base_img.dE76(test_img)
      end

      # Create a boolean mask: 255 where diff > color tolerance, 0 otherwise
      thresholded_diff = diff > color_tol

      # .avg returns the average pixel value (between 0 and 255).
      # Dividing by 255 gives us the exact ratio of pixels that failed the color check.
      changed_ratio = thresholded_diff.avg / 255.0

      if changed_ratio > pixel_tol
        {
          match: false,
          reason: "Visual mismatch: #{(changed_ratio * 100).round(4)}% of pixels differ (Threshold: #{pixel_tol * 100}%)."
        }
      else
        {
          match: true,
          reason: "Match: Differences are within accepted anti-aliasing and masking thresholds."
        }
      end
    end
  end
end

# --- Example Usage ---
if __FILE__ == $PROGRAM_NAME
  result = VisualRegression::Comparator.compare(
    'baseline.png',
    'latest_render.png',
    masks: [
      [1500, 50, 300, 250], # Mask out an ad banner top right
      [10, 10, 100, 20]     # Mask out a timestamp top left
    ],
    size_tolerance: 0.05,   # 5% file size jump allowed before instant fail
    color_tolerance: 2.0,   # DE2000 > 2.0 triggers a mismatch
    pixel_tolerance: 0.001  # Allow 0.1% of the image's pixels to differ (stray noise)
  )

  puts result.inspect
end
