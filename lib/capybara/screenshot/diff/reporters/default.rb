# frozen_string_literal: true

module Capybara::Screenshot::Diff
  module Reporters
    class Default
      attr_reader :annotated_image_path, :annotated_base_image_path, :difference

      def initialize(difference)
        @difference = difference

        @annotated_image_path = comparison.new_image_path.sub_ext(".diff.png")
        @annotated_base_image_path = comparison.base_image_path.sub_ext(".diff.png")
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
        annotated_base_image_path.unlink if annotated_base_image_path.exist?
        annotated_image_path.unlink if annotated_image_path.exist?
      end

      def build_error_for_different_dimensions
        change_msg = [comparison.base_image, comparison.new_image]
          .map { |image| driver.dimension(image).join("x") }
          .join(" => ")

        "Screenshot dimension has been changed for #{new_file_name}: #{change_msg}"
      end

      def annotate_and_save_images
        annotate_and_save_image(difference.comparison.new_image, annotated_image_path)
        annotate_and_save_image(difference.comparison.base_image, annotated_base_image_path)
      end

      def annotate_and_save_image(image, image_path)
        image = annotate_difference(image, difference.region)
        image = annotate_skip_areas(image, difference.skip_area) if difference.skip_area

        save(image, image_path.to_path)
      end

      DIFF_COLOR = [255, 0, 0, 255].freeze

      def annotate_difference(image, region)
        driver.draw_rectangles([image], region, DIFF_COLOR, offset: 1).first
      end

      SKIP_COLOR = [255, 192, 0, 255].freeze

      def annotate_skip_areas(image, skip_areas)
        skip_areas.reduce(image) do |memo, region|
          driver.draw_rectangles([memo], region, SKIP_COLOR).first
        end
      end

      def save(image, image_path)
        driver.save_image_to(image, image_path.to_s)
      end

      NEW_LINE = "\n".freeze

      def build_error_message
        [
          "(#{difference.inspect})",
          new_image_path.to_path,
          annotated_base_image_path.to_path,
          annotated_image_path.to_path
        ].join(NEW_LINE)
      end

      private

      def new_image_path
        comparison.new_image_path
      end

      def driver
        @_driver ||= comparison.driver
      end

      def comparison
        @_comparison ||= difference.comparison
      end

      def new_file_name
        @_new_file_name ||= comparison.new_image_path.to_path
      end
    end
  end
end
