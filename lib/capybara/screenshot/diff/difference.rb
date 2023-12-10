# frozen_string_literal: true

require "json"

module Capybara
  module Screenshot
    module Diff
      class Difference < Struct.new(:region, :meta, :comparison, :failed_by)
        def different?
          failed? || !(blank? || tolerable?)
        end

        def failed?
          !!failed_by
        end

        def base_image
          comparison.base_image
        end

        def options
          comparison.options
        end

        def tolerance
          options[:tolerance]
        end

        def skip_area
          options[:skip_area]
        end

        def area_size_limit
          options[:area_size_limit]
        end

        def blank?
          region.nil? || region_area_size.zero?
        end

        def region_area_size
          region&.size || 0
        end

        def ratio
          meta[:difference_level]
        end

        def to_h
          {area_size: region_area_size, region: coordinates}.merge!(meta)
        end

        def coordinates
          region&.to_edge_coordinates
        end

        def inspect
          to_h.to_json
        end

        def tolerable?
          !!((area_size_limit && area_size_limit >= region_area_size) || (tolerance && tolerance >= ratio))
        end
      end
    end
  end
end
