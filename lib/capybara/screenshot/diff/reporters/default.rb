# frozen_string_literal: true

module Capybara::Screenshot::Diff
  module Reporters
    class Default
      attr_reader :comparer, :annotated_image_path, :annotated_base_image_path

      def initialize(comparer, annotated_image_path = nil, annotated_base_image_path = nil)
        @comparer = comparer
        @annotated_image_path = annotated_image_path || comparer.annotated_image_path
        @annotated_base_image_path = annotated_base_image_path || comparer.annotated_base_image_path
      end

      def generate(difference)
        return nil unless difference.different?

        if difference.failed? && difference.failed_by[:different_dimensions]
          return build_error_for_different_dimensions(difference.failed_by[:different_dimensions])
        end

        annotate_and_save_images(difference)
        build_error_message(difference)
      end


      def clean_tmp_files
        annotated_base_image_path.unlink if annotated_base_image_path.exist?
        annotated_image_path.unlink if annotated_image_path.exist?
      end

      def build_error_for_different_dimensions(failed_by)
        comparison, new_file_name = failed_by[:comparison], failed_by[:new_file_name]
        change_msg = [comparison.base_image, comparison.new_image]
          .map { |i| driver.dimension(i).join("x") }
          .join(" => ")

        "Screenshot dimension has been changed for #{new_file_name}: #{change_msg}"
      end

      def annotate_and_save_images(difference)
        annotate_and_save_image(difference, difference.comparison.new_image, annotated_image_path)
        annotate_and_save_image(difference, difference.comparison.base_image, annotated_base_image_path)
      end

      def annotate_and_save_image(difference, image, image_path)
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

      def build_error_message(difference)
        [
          "(#{difference.inspect})",
          new_file_name,
          annotated_base_image_path.to_path,
          annotated_image_path.to_path
        ].join(NEW_LINE)
      end

      private

      def reporter
        self
      end

      def driver
        @comparer.driver
      end

      def new_file_name
        @comparer.new_file_name
      end
    end
  end
end
