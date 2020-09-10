# frozen_string_literal: true

require 'English'
require 'capybara'
require 'action_controller'
require 'action_dispatch'
require 'active_support/core_ext/string/strip'
require_relative 'image_compare'
require_relative 'stabilization'
require_relative 'vcs'

# Add the `screenshot` method to ActionDispatch::IntegrationTest
module Capybara
  module Screenshot
    module Diff
      module TestMethods
        include Stabilization
        include Vcs

        def initialize(*)
          super
          @screenshot_counter = nil
          @screenshot_group = nil
          @screenshot_section = nil
          @test_screenshot_errors = nil
          @test_screenshots = nil
        end

        def group_parts
          parts = []
          parts << @screenshot_section if @screenshot_section.present?
          parts << @screenshot_group if @screenshot_group.present?
          parts
        end

        def full_name(name)
          File.join group_parts.<<(name).map(&:to_s)
        end

        def screenshot_dir
          File.join [Screenshot.screenshot_area] + group_parts
        end

        def current_capybara_driver_class
          Capybara.current_session.driver.class
        end

        def selenium?
          current_capybara_driver_class <= Capybara::Selenium::Driver
        end

        def poltergeist?
          return false unless defined?(Capybara::Poltergeist::Driver)

          current_capybara_driver_class <= Capybara::Poltergeist::Driver
        end

        def screenshot_section(name)
          @screenshot_section = name.to_s
        end

        def screenshot_group(name)
          @screenshot_group = name.to_s
          @screenshot_counter = 0
          return unless Screenshot.active? && name.present?

          FileUtils.rm_rf screenshot_dir
        end

        # @return [Boolean] wether a screenshot was taken
        def screenshot(
          name,
          stability_time_limit: Screenshot.stability_time_limit,
          wait: Capybara.default_max_wait_time,
          **driver_options
        )
          return false unless Screenshot.active?
          return false if window_size_is_wrong?

          driver_options = {
            area_size_limit: Diff.area_size_limit,
            color_distance_limit: Diff.color_distance_limit,
            driver: Diff.driver,
            shift_distance_limit: Diff.shift_distance_limit,
            skip_area: Diff.skip_area,
            tolerance: Diff.tolerance
          }.merge(driver_options)

          # Allow nil or single or multiple areas
          if driver_options[:skip_area]
            driver_options[:skip_area] = driver_options[:skip_area].compact.flatten&.each_cons(4)&.to_a
          end

          if @screenshot_counter
            name = "#{format('%02i', @screenshot_counter)}_#{name}"
            @screenshot_counter += 1
          end
          name = full_name(name)
          file_name = "#{Screenshot.screenshot_area_abs}/#{name}.png"

          FileUtils.mkdir_p File.dirname(file_name)
          comparison = ImageCompare.new(file_name, **driver_options)
          checkout_vcs(name, comparison)
          take_stable_screenshot(comparison, stability_time_limit: stability_time_limit, wait: wait)

          return false unless comparison.old_file_exists?

          (@test_screenshots ||= []) << [caller(1..1).first, name, comparison]

          true
        end

        def window_size_is_wrong?
          selenium? && Screenshot.window_size &&
            page.driver.browser.manage.window.size !=
              ::Selenium::WebDriver::Dimension.new(*Screenshot.window_size)
        end

        def assert_image_not_changed(caller, name, comparison)
          return unless comparison.different?

          "Screenshot does not match for '#{name}' #{comparison.error_message}\nat #{caller}"
        end
      end
    end
  end
end
