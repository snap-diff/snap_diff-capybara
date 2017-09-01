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
      mattr_accessor :area_size_limit
      mattr_accessor :color_distance_limit
      mattr_accessor(:enabled) { true }
    end
  end
end
