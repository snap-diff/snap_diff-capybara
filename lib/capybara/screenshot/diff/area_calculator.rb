# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      class AreaCalculator
        def initialize(crop_coordinates, skip_area)
          @crop_coordinates = crop_coordinates
          @skip_area = skip_area
        end

        def calculate_crop
          return @_calculated_crop if defined?(@_calculated_crop)
          return @_calculated_crop = nil unless @crop_coordinates

          # TODO: Move out from this class, this should be done on before screenshot and should not depend on Browser
          @crop_coordinates = BrowserHelpers.bounds_for_css(@crop_coordinates).first if @crop_coordinates.is_a?(String)
          @_calculated_crop = Region.from_edge_coordinates(*@crop_coordinates)
        end

        # Cast skip areas params into Region
        # and if there is crop then makes absolute coordinates to eb relative to crop top left corner
        def calculate_skip_area
          return nil unless @skip_area

          crop_region = calculate_crop
          skip_area = Array(@skip_area)

          css_selectors, coords_list = skip_area.compact.partition { |region| region.is_a? String }
          regions, coords_list = coords_list.partition { |region| region.is_a? Region }

          regions.concat(build_regions_for(BrowserHelpers.bounds_for_css(*css_selectors))) unless css_selectors.empty?
          regions.concat(build_regions_for(coords_list.flatten.each_slice(4))) unless coords_list.empty?

          regions.compact!

          if crop_region
            regions
              .map! { |region| crop_region.find_relative_intersect(region) }
              .filter! { |region| region&.present? }
          end

          regions
        end

        private

        def build_regions_for(coordinates)
          coordinates
            .map { |entry| Region.from_edge_coordinates(*entry) }
            .tap { |region| region.compact! }
        end
      end
    end
  end
end
