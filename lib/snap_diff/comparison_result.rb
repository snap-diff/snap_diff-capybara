# frozen_string_literal: true

require "json"

module SnapDiff
  # Represents the result of comparing two images
  #
  # This value object encapsulates the result of an image comparison operation.
  # It follows the Single Responsibility Principle by focusing solely on representing
  # the difference state, including:
  # - Whether images are different or equal
  # - Why they differ (dimensions, pixels, etc.)
  # - The specific region of difference
  # - Whether differences are tolerable based on configured thresholds
  #
  # As part of the layered comparison architecture, this class represents the final
  # output of the comparison process, containing all data needed for reporting.
  class ComparisonResult < Struct.new(:region, :meta, :comparison, :failed_by, :base_image_path, :image_path, keyword_init: nil)
    def self.build_null(comparison, base_image_path, new_image_path, failed_by = nil)
      ComparisonResult.new(
        nil,
        {difference_level: nil, max_color_distance: 0},
        comparison,
        failed_by,
        base_image_path,
        new_image_path
      ).freeze
    end

    def different?
      failed? || !(blank? || tolerable?)
    end

    def equal?
      !different?
    end

    def failed?
      !!failed_by
    end

    def options
      comparison.options
    end

    def tolerance
      options[:tolerance]
    end

    def skip_area
      comparison.skip_area
    end

    def area_size_limit
      options[:area_size_limit]
    end

    def blank?
      region.nil? || region_area_size.zero?
    end

    def region_area_size
      @region_area_size ||= region&.size || 0
    end

    def ratio
      meta[:difference_level]
    end

    # Serializable difference metrics. The raw diff mask image is excluded —
    # it is an image object, not a metric, and is reachable via #diff_mask.
    def to_h
      {area_size: region_area_size, region: coordinates}.merge!(meta.except(:diff_mask))
    end

    def coordinates
      region&.to_edge_coordinates
    end

    # One-line debugging summary with the difference metrics.
    # (Error messages use #to_h — see Reporters::Default#build_error_message.)
    def inspect
      "#<#{self.class.name} different=#{different?} failed_by=#{failed_by.inspect} " \
        "area_size=#{region_area_size} region=#{coordinates.inspect} " \
        "difference_level=#{ratio.inspect} " \
        "base=#{original_image_path} new=#{new_image_path}>"
    end

    def tolerable?
      !!((area_size_limit && area_size_limit >= region_area_size) || (tolerance && tolerance >= ratio))
    end

    # Path accessors for backward compatibility
    def new_image_path
      image_path || comparison&.new_image_path
    end

    def original_image_path
      base_image_path || comparison&.base_image_path
    end

    def diff_mask
      meta[:diff_mask]
    end
  end
end
