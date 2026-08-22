# frozen_string_literal: true

module SnapDiff
  # Draws diff/skip-area rectangles and the heatmap overlay for a Difference,
  # and saves the resulting images to their `.diff.*` / `.heatmap.diff.*` paths.
  #
  # Extracted from Reporters::Default (ADR-004 PR 7) so the reporter only
  # builds error messages; this class owns all image annotation work.
  class AnnotationService
    attr_reader :annotated_image_path, :annotated_base_image_path, :heatmap_diff_path

    def initialize(difference)
      @difference = difference

      comparison = difference.comparison
      ext = comparison.new_image_path.extname.delete_prefix(".")
      screenshot_format = comparison.options[:screenshot_format] || (ext unless ext.empty?) || "png"
      @annotated_image_path = comparison.new_image_path.sub_ext(".diff.#{screenshot_format}")
      @annotated_base_image_path = comparison.base_image_path.sub_ext(".diff.#{screenshot_format}")
      @heatmap_diff_path = comparison.new_image_path.sub_ext(".heatmap.diff.#{screenshot_format}")
    end

    def clean_tmp_files
      annotated_base_image_path.unlink if annotated_base_image_path.exist?
      annotated_image_path.unlink if annotated_image_path.exist?
      heatmap_diff_path.unlink if heatmap_diff_path.exist?
    end

    def annotate_and_save_images
      save_annotation_for(new_image, annotated_image_path)
      save_annotation_for(base_image, annotated_base_image_path)
      save_heatmap_diff if difference.diff_mask
    end

    def save_annotation_for(image, image_path)
      image = annotate_difference(image, difference.region)
      image = annotate_skip_areas(image, difference.comparison.skip_area) if difference.comparison.skip_area

      save(image, image_path.to_path)
    end

    def annotate_difference(image, region)
      driver.draw_rectangles([image], region, CapybaraScreenshotDiff::RED_RGBA, offset: 1).first
    end

    def annotate_skip_areas(image, skip_areas)
      skip_areas.reduce(image) do |memo, region|
        driver.draw_rectangles([memo], region, CapybaraScreenshotDiff::ORANGE_RGBA).first
      end
    end

    def save(image, image_path)
      driver.save_image_to(image, image_path.to_s)
    end

    private

    attr_reader :difference

    def save_heatmap_diff
      merged_image = driver.merge(new_image, base_image)
      highlighted_mask = driver.highlight_mask(difference.diff_mask, merged_image, color: CapybaraScreenshotDiff::RED_RGBA)

      save(highlighted_mask, heatmap_diff_path.to_path)
    end

    def base_image
      difference.comparison.base_image
    end

    def new_image
      difference.comparison.new_image
    end

    def driver
      @_driver ||= difference.comparison.driver
    end
  end
end
