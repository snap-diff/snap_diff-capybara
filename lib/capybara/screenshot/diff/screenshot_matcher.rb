# frozen_string_literal: true

require_relative "screenshoter"
require_relative "stable_screenshoter"
require_relative "browser_helpers"
require_relative "vcs"

module Capybara
  module Screenshot
    module Diff
      class ScreenshotMatcher
        attr_reader :screenshot_full_name, :driver_options, :screenshot_path, :base_screenshot_path, :screenshot_format

        def initialize(screenshot_full_name, options = {})
          @screenshot_full_name = screenshot_full_name
          @driver_options = Diff.default_options.merge(options)

          @screenshot_format = @driver_options[:screenshot_format]
          @screenshot_path = Screenshot.screenshot_area_abs / Pathname.new(screenshot_full_name).sub_ext(".#{screenshot_format}")
          @base_screenshot_path = ScreenshotMatcher.base_image_path_from(@screenshot_path)
        end

        def build_screenshot_matches_job
          # TODO: Move this into screenshot stage, in order to re-evaluate coordinates after page updates
          return if BrowserHelpers.window_size_is_wrong?(Screenshot.window_size)

          # Stability Screenshoter Options

          # TODO: Move this into screenshot stage, in order to re-evaluate coordinates after page updates
          crop = calculate_crop_region(driver_options)

          # Allow nil or single or multiple areas
          # TODO: Move this into screenshot stage, in order to re-evaluate coordinates after page updates
          if driver_options[:skip_area]
            # Cast skip area args to Region and makes relative to crop
            driver_options[:skip_area] = calculate_skip_area(driver_options[:skip_area], crop)
          end
          driver_options[:driver] = Drivers.for(driver_options)

          create_output_directory_for(screenshot_path) unless screenshot_path.exist?

          checkout_base_screenshot

          capture_options = {
            crop: crop,
            stability_time_limit: driver_options.delete(:stability_time_limit),
            wait: driver_options.delete(:wait),
            screenshot_format: driver_options[:screenshot_format]
          }

          take_comparison_screenshot(capture_options, driver_options, screenshot_path)

          return unless base_screenshot_path.exist?

          # Add comparison job in the queue
          [
            screenshot_full_name,
            ImageCompare.new(screenshot_path.to_s, base_screenshot_path.to_s, driver_options)
          ]
        end

        def self.base_image_path_from(screenshot_path)
          screenshot_path.sub_ext(".base#{screenshot_path.extname}")
        end

        private

        def checkout_base_screenshot
          Vcs.checkout_vcs(screenshot_path, base_screenshot_path)
        end

        def calculate_crop_region(driver_options)
          crop_coordinates = driver_options.delete(:crop)
          return nil unless crop_coordinates

          crop_coordinates = BrowserHelpers.bounds_for_css(crop_coordinates).first if crop_coordinates.is_a?(String)
          Region.from_edge_coordinates(*crop_coordinates)
        end

        def create_output_directory_for(screenshot_path)
          screenshot_path.dirname.mkpath
        end

        # Try to get screenshot from browser.
        # On `stability_time_limit` it checks that page stop updating by comparison several screenshot attempts
        # On reaching `wait` limit then it has been failed. On failing we annotate screenshot attempts to help to debug
        def take_comparison_screenshot(capture_options, driver_options, screenshot_path)
          screenshoter = build_screenshoter_for(capture_options, driver_options)
          screenshoter.take_comparison_screenshot(screenshot_path)
        end

        def build_screenshoter_for(capture_options, comparison_options = {})
          if capture_options[:stability_time_limit]
            StableScreenshoter.new(capture_options, comparison_options)
          else
            Diff.screenshoter.new(capture_options, comparison_options[:driver])
          end
        end

        # Cast skip areas params into Region
        # and if there is crop then makes absolute coordinates to eb relative to crop top left corner
        def calculate_skip_area(skip_area, crop)
          crop_region = crop && Region.new(*crop)
          skip_area = Array(skip_area)

          css_selectors, regions = skip_area.compact.partition { |region| region.is_a? String }

          result = []
          unless css_selectors.empty?
            result.concat(build_regions_for(BrowserHelpers.bounds_for_css(*css_selectors)))
          end
          result.concat(build_regions_for(regions.flatten.each_slice(4))) unless regions.empty?
          result.compact!

          result.map! { |region| crop_region.find_relative_intersect(region) } if crop_region

          result
        end

        def build_regions_for(coordinates)
          coordinates.map { |coordinates_entity| Region.from_edge_coordinates(*coordinates_entity) }
        end
      end
    end
  end
end
