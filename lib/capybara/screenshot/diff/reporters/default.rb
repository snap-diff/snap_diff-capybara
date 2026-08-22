# frozen_string_literal: true

require "snap_diff/annotation_service"
# Defines the Capybara::Screenshot::Diff namespace this file reopens.
require "snap_diff/legacy_shims"

module Capybara::Screenshot::Diff
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

      def save_annotation_for(image, image_path)
        annotation_service.save_annotation_for(image, image_path)
      end

      def annotate_difference(image, region)
        annotation_service.annotate_difference(image, region)
      end

      def annotate_skip_areas(image, skip_areas)
        annotation_service.annotate_skip_areas(image, skip_areas)
      end

      def save(image, image_path)
        annotation_service.save(image, image_path)
      end

      def build_error_for_different_dimensions
        change_msg = [comparison.base_image, comparison.new_image]
          .map { |image| driver.dimension(image).join("x") }
          .join(" => ")

        "Dimensions have changed: #{change_msg}\n#{base_image_path.to_path}\n#{image_path.to_path}"
      end

      NEW_LINE = "\n"

      def build_error_message
        [
          "(#{difference.to_h.to_json})",
          image_path.to_path,
          annotated_base_image_path.to_path,
          annotated_image_path.to_path,
          heatmap_diff_path.to_path
        ].join(NEW_LINE)
      end

      private

      attr_reader :annotation_service

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
