require 'capybara/dsl'
require 'capybara/screenshot/diff/version'
require 'capybara/screenshot/diff/image_compare'
require 'capybara/screenshot/diff/test_methods'

module Capybara
  module Screenshot
    extend Os
    mattr_accessor :add_driver_path
    mattr_accessor :add_os_path
    mattr_accessor :blur_active_element
    mattr_accessor :enabled
    mattr_accessor(:screenshot_root) { (defined?(Rails.root) && Rails.root) || File.expand_path('.') }
    mattr_accessor :stability_time_limit
    mattr_accessor :window_size

    class << self
      def active?
        enabled || (enabled.nil? && Diff.enabled)
      end

      def screenshot_area
        parts = ['doc/screenshots']
        parts << Capybara.default_driver.to_s if Capybara::Screenshot.add_driver_path
        parts << os_name if Capybara::Screenshot.add_os_path
        File.join parts
      end

      def screenshot_area_abs
        "#{screenshot_root}/#{screenshot_area}".freeze
      end
    end

    # Module to track screen shot changes
    module Diff
      include Capybara::DSL
      include Capybara::Screenshot::Os

      mattr_accessor :area_size_limit
      mattr_accessor :color_distance_limit
      mattr_accessor(:enabled) { true }

      def self.included(clas)
        clas.include TestMethods
        clas.setup do
          if Capybara::Screenshot.window_size
            if selenium?
              page.driver.browser.manage.window.resize_to(*Capybara::Screenshot.window_size)
            elsif poltergeist?
              page.driver.resize(*Capybara::Screenshot.window_size)
            end
          end
        end

        clas.teardown do
          if Capybara::Screenshot::Diff.enabled && @test_screenshots
            test_screenshot_errors = @test_screenshots
              .map { |caller, name, compare| assert_image_not_changed(caller, name, compare) }.compact
            fail(test_screenshot_errors.join("\n\n")) if test_screenshot_errors.any?
          end
        end
      end
    end
  end
end
