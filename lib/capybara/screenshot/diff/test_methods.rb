require 'English'
require 'capybara'
require 'action_controller'
require 'action_dispatch'
require 'active_support/core_ext/string/strip'
require_relative 'image_compare'
require_relative 'stabilization'
require_relative 'vcs'

# TODO(uwe): Move this code to module Capybara::Screenshot::Diff::TestMethods,
#            and use Module#prepend/include to insert.
# Add the `screenshot` method to ActionDispatch::IntegrationTest
module Capybara
  module Screenshot
    module Diff
      module TestMethods
        include Capybara::Screenshot::Diff::Stabilization
        include Capybara::Screenshot::Diff::Vcs

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
          File.join [Capybara::Screenshot.screenshot_area] + group_parts
        end

        def current_capybara_driver_class
          Capybara.drivers[Capybara.current_driver].call({}).class
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
          return unless Capybara::Screenshot.active? && name.present?
          FileUtils.rm_rf screenshot_dir
        end

        def screenshot(name, color_distance_limit: Capybara::Screenshot::Diff.color_distance_limit,
            area_size_limit: nil)
          return unless Capybara::Screenshot.active?
          return if window_size_is_wrong?
          if @screenshot_counter
            name = "#{format('%02i', @screenshot_counter)}_#{name}"
            @screenshot_counter += 1
          end
          name = full_name(name)
          file_name = "#{Capybara::Screenshot.screenshot_area_abs}/#{name}.png"

          FileUtils.mkdir_p File.dirname(file_name)
          comparison = Capybara::Screenshot::Diff::ImageCompare.new(file_name,
              dimensions: Capybara::Screenshot.window_size, color_distance_limit: color_distance_limit,
              area_size_limit: area_size_limit)
          checkout_vcs(name, comparison)
          take_stable_screenshot(comparison)
          return unless comparison.old_file_exists?
          (@test_screenshots ||= []) << [caller(1..1).first, name, comparison]
        end

        def window_size_is_wrong?
          selenium? && Capybara::Screenshot.window_size &&
            (!page.driver.chrome? || ON_WINDOWS) && # TODO(uwe): Allow for Chrome when it works
            page.driver.browser.manage.window.size !=
              Selenium::WebDriver::Dimension.new(*Capybara::Screenshot.window_size)
        end

        def assert_image_not_changed(caller, name, comparison)
          return unless comparison.different?

          # TODO(uwe): Remove check when we stop supporting Ruby 2.3 and older
          max_color_distance = if RUBY_VERSION >= '2.4'
                                 comparison.max_color_distance.ceil(1)
                               else
                                 comparison.max_color_distance.ceil
                               end
          # ODOT

          "Screenshot does not match for '#{name}' (area: #{comparison.size}px #{comparison.dimensions}" \
            ", max_color_distance: #{max_color_distance})\n" \
            "#{comparison.new_file_name}\n#{comparison.annotated_old_file_name}\n" \
            "#{comparison.annotated_new_file_name}\n" \
            "at #{caller}"
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength

module ActionDispatch
  class IntegrationTest
    prepend Capybara::Screenshot::Diff::TestMethods

    setup do
      if Capybara::Screenshot.window_size
        if selenium?
          # TODO(uwe): Enable for Chrome and non-windows when it works)
          if !page.driver.chrome? || ON_WINDOWS
            page.driver.browser.manage.window.resize_to(*Capybara::Screenshot.window_size)
          end
        elsif poltergeist?
          page.driver.resize(*Capybara::Screenshot.window_size)
        end
      end
    end

    teardown do
      if Capybara::Screenshot::Diff.enabled && @test_screenshots
        test_screenshot_errors = @test_screenshots
          .map { |caller, name, compare| assert_image_not_changed(caller, name, compare) }.compact
        fail(test_screenshot_errors.join("\n\n")) if test_screenshot_errors.any?
      end
    end
  end
end
