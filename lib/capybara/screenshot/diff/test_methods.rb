# frozen_string_literal: true

require "English"
require "capybara"
require "action_controller"
require "action_dispatch"
require "active_support/core_ext/string/strip"
require_relative "image_compare"
require_relative "stabilization"
require_relative "vcs"
require_relative "browser_helpers"
require_relative "region"

# Add the `screenshot` method to ActionDispatch::IntegrationTest
module Capybara
  module Screenshot
    module Diff
      module TestMethods
        include Stabilization
        include Vcs
        include BrowserHelpers

        def initialize(*)
          super
          @screenshot_counter = nil
          @screenshot_group = nil
          @screenshot_section = nil
          @test_screenshot_errors = nil
          @test_screenshots = nil
        end

        # @param [(Symbol | String)] name
        # @return [String]
        def full_name(name)
          File.join *group_parts.push(name.to_s)
        end

        # @return [String]
        def screenshot_dir
          File.join *([Screenshot.screenshot_area] + group_parts)
        end

        # @param [(Symbol | String)] name
        def screenshot_section(name)
          @screenshot_section = name.to_s
        end

        # @param [(Symbol | String)] name of the group
        def screenshot_group(name)
          @screenshot_group = name.to_s
          @screenshot_counter = 0
          return unless Screenshot.active? && name.present?

          FileUtils.rm_rf screenshot_dir
        end

        # @param [(Symbol | String)] name
        # @param [Integer] skip_stack_frames
        # @param [**untyped] options
        # @return [Boolean] whether a screenshot was taken
        def screenshot(name, skip_stack_frames: 0, **options)
          return false unless Screenshot.active?
          return false if window_size_is_wrong?

          driver_options = Diff.default_options.merge(options)

          stability_time_limit = driver_options[:stability_time_limit]
          wait = driver_options[:wait]
          crop = calculate_crop_region(driver_options)

          if @screenshot_counter
            name = "#{format("%02i", @screenshot_counter)}_#{name}"
            @screenshot_counter += 1
          end
          name = full_name(name)
          file_name = "#{Screenshot.screenshot_area_abs}/#{name}.png"

          create_output_directory_for(file_name)

          comparison = ImageCompare.new(file_name, nil, driver_options)
          checkout_vcs(name, comparison.old_file_name, comparison.new_file_name)

          return false unless comparison.old_file_exists?

          # Allow nil or single or multiple areas
          if driver_options[:skip_area]
            comparison.skip_area = calculate_skip_area(driver_options[:skip_area], crop)
          end

          take_comparison_screenshot(comparison, crop, stability_time_limit, wait)

          (@test_screenshots ||= []) << [caller[skip_stack_frames], name, comparison]

          true
        end

        def assert_image_not_changed(caller, name, comparison)
          return nil unless comparison.different?

          "Screenshot does not match for '#{name}' #{comparison.error_message}\nat #{caller}"
        end

        private

        def group_parts
          parts = []
          parts << @screenshot_section if @screenshot_section.present?
          parts << @screenshot_group if @screenshot_group.present?
          parts
        end

        def calculate_crop_region(driver_options)
          crop_coordinates = driver_options.delete(:crop)
          return nil unless crop_coordinates

          crop_coordinates = bounds_for_css(crop_coordinates).first if crop_coordinates.is_a?(String)
          Region.from_edge_coordinates(*crop_coordinates)
        end

        def create_output_directory_for(file_name)
          FileUtils.mkdir_p File.dirname(file_name)
        end

        def take_comparison_screenshot(comparison, crop, stability_time_limit, wait)
          blurred_input = prepare_page_for_screenshot(timeout: wait)
          if stability_time_limit
            take_stable_screenshot(
              comparison,
              crop: crop,
              stability_time_limit: stability_time_limit,
              wait: wait
            )
          else
            take_right_size_screenshot(comparison, crop: crop)
          end
        ensure
          blurred_input&.click
        end

        def calculate_skip_area(skip_area, crop)
          crop_region = crop && Region.new(*crop)
          skip_area = Array(skip_area)

          css_selectors, regions = skip_area.compact.partition { |region| region.is_a? String }

          result = []
          result.concat(build_regions_for(bounds_for_css(*css_selectors))) unless css_selectors.empty?
          result.concat(build_regions_for(regions.flatten.each_slice(4))) unless regions.empty?
          result.compact!

          result.map! { |region| crop_region.find_relative_intersect(region) } if crop_region

          result
        end

        def build_regions_for(coordinates)
          coordinates.map do |region_coordinates|
            Region.from_edge_coordinates(*region_coordinates)
          end
        end
      end
    end
  end
end
