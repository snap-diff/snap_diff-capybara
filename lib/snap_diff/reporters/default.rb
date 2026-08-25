# frozen_string_literal: true

require "json"

require "snap_diff/annotation_service"
# For SnapDiff.config.root, the base for the relative artifact paths below.
require "snap_diff/config"

module SnapDiff
  module Reporters
    class Default
      attr_reader :difference

      def initialize(difference)
        @difference = difference
        @annotation_service = SnapDiff::AnnotationService.new(difference)
      end

      def annotated_image_path
        annotation_service.annotated_image_path
      end

      def annotated_base_image_path
        annotation_service.annotated_base_image_path
      end

      def heatmap_diff_path
        annotation_service.heatmap_diff_path
      end

      def generate
        if difference.equal?
          # NOTE: Delete previous run runtime files
          clean_tmp_files
          return nil
        end

        if difference.failed? && difference.failed_by[:different_dimensions]
          return build_error_for_different_dimensions
        end

        annotate_and_save_images
        build_error_message
      end

      def clean_tmp_files
        annotation_service.clean_tmp_files
      end

      def annotate_and_save_images
        annotation_service.annotate_and_save_images
      end

      def build_error_for_different_dimensions
        change_msg = [comparison.base_image, comparison.new_image]
          .map { |image| driver.dimension(image).join("x") }
          .join(" => ")

        "Dimensions have changed: #{change_msg}\n#{base_image_path.to_path}\n#{image_path.to_path}"
      end

      NEW_LINE = "\n"

      # The one place the gem turns a fraction of the image into prose.
      # Public because AttemptsReporter reports the same kind of number and
      # must say it the same way (#264 vocabulary).
      def self.percent(fraction)
        value = fraction * 100
        (value.positive? && value < 0.01) ? "<0.01%" : format("%.2f%%", value)
      end

      # The thresholds a comparison is judged against, in the order they read
      # best. Only the ones actually set are printed -- see #thresholds.
      THRESHOLDS = [
        :tolerance,
        :area_size_limit,
        :color_distance_limit,
        :shift_distance_limit,
        :perceptual_threshold
      ].freeze

      # The five artifacts a comparison can leave on disk, in the order a
      # reader wants them: the two inputs first, then what we drew on them.
      ARTIFACT_LABELS = {
        "baseline" => :base_image_path,
        "actual" => :image_path,
        "baseline annotated" => :annotated_base_image_path,
        "actual annotated" => :annotated_image_path,
        "heatmap" => :heatmap_diff_path
      }.freeze

      def build_error_message
        [headline, *metric_lines, *artifact_lines].join(NEW_LINE)
      end

      private

      attr_reader :annotation_service

      # Reads as the tail of "Screenshot does not match for 'name': ".
      def headline
        width, height = driver.dimension(comparison.base_image)
        total_pixels = width * height
        area = difference.region_area_size

        "the change spans #{area.round} of #{total_pixels} px " \
          "(#{percent(area.to_f / total_pixels)} of the #{width}x#{height} image)"
      end

      def metric_lines
        lines = ["  changed region: #{difference.coordinates.to_json} (left,top,right,bottom edges)"]
        # difference_level is the changed share of the image area -- the
        # number `tolerance` is compared against. Only computed when a
        # tolerance is set, so only printed then.
        if difference.ratio
          lines << "  difference level: #{difference.ratio} (#{percent(difference.ratio)} of the image area)"
        end
        max_color_distance = difference.meta[:max_color_distance]
        lines << "  max color distance: #{max_color_distance}" if max_color_distance&.positive?
        max_shift_distance = difference.meta[:max_shift_distance]
        lines << "  max shift distance: #{max_shift_distance} px" if max_shift_distance&.positive?
        lines << "  judged against: #{thresholds}"
      end

      def thresholds
        applied = THRESHOLDS.filter_map do |name|
          value = difference.options[name]
          "#{name} #{value}" if value
        end

        applied.empty? ? "no tolerance thresholds configured (any difference fails)" : applied.join(", ")
      end

      # Only what is on disk gets a line: the heatmap exists solely for
      # drivers that produce a diff mask, and a comparison can be reported
      # before either input has been written out.
      def artifact_lines
        present = ARTIFACT_LABELS.filter_map do |label, path_method|
          path = send(path_method)
          [label, path] if path.exist?
        end
        width = present.map { |label, _path| label.length }.max.to_i

        present.map { |label, path| "  #{"#{label}:".ljust(width + 1)} #{display_path(path)}" }
      end

      # Relative to the configured root: shorter to read, and still
      # click-through-able in terminals that resolve paths against the
      # working directory. Anything outside the root stays absolute, because
      # a "../../.." path is neither.
      def display_path(path)
        relative = path.expand_path.relative_path_from(SnapDiff.config.root).to_path
        relative.start_with?("..") ? path.to_path : relative
      end

      def percent(fraction)
        self.class.percent(fraction)
      end

      def base_image_path
        comparison.base_image_path
      end

      def image_path
        comparison.new_image_path
      end

      def driver
        @_driver ||= comparison.driver
      end

      def comparison
        @_comparison ||= difference.comparison
      end
    end
  end
end
