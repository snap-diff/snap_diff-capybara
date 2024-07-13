# frozen_string_literal: true

require "capybara/dsl"
require "capybara/screenshot/diff/version"
require "capybara/screenshot/diff/utils"
require "capybara/screenshot/diff/image_compare"
require "capybara/screenshot/diff/test_methods"
require "capybara/screenshot/diff/screenshoter"

require "capybara/screenshot/diff/reporters/default"

module Capybara
  module Screenshot
    mattr_accessor :add_driver_path
    mattr_accessor :add_os_path
    mattr_accessor :blur_active_element
    mattr_accessor :enabled
    mattr_accessor :hide_caret
    mattr_reader(:root) { (defined?(Rails.root) && Rails.root) || Pathname(".").expand_path }
    mattr_accessor :stability_time_limit
    mattr_accessor :window_size
    mattr_accessor(:save_path) { "doc/screenshots" }
    mattr_accessor(:use_lfs)
    mattr_accessor(:screenshot_format) { "png" }
    mattr_accessor(:capybara_screenshot_options) { {} }

    class << self
      def root=(path)
        @@root = Pathname(path).expand_path
      end

      def active?
        enabled || (enabled.nil? && Diff.enabled)
      end

      def screenshot_area
        parts = [Screenshot.save_path]
        parts << Os.name if Screenshot.add_os_path
        parts << Capybara.current_driver.to_s if Screenshot.add_driver_path
        File.join(*parts)
      end

      def screenshot_area_abs
        root / screenshot_area
      end
    end

    # Module to track screen shot changes
    module Diff
      include Capybara::DSL

      mattr_accessor(:delayed) { true }
      mattr_accessor :area_size_limit
      mattr_accessor(:fail_if_new) { false }
      mattr_accessor(:fail_on_difference) { true }
      mattr_accessor :color_distance_limit
      mattr_accessor(:enabled) { true }
      mattr_accessor :shift_distance_limit
      mattr_accessor :skip_area
      mattr_accessor(:driver) { :auto }
      mattr_accessor :tolerance

      mattr_accessor(:screenshoter) { Screenshoter }

      AVAILABLE_DRIVERS = Utils.detect_available_drivers.freeze

      def self.default_options
        {
          area_size_limit: area_size_limit,
          color_distance_limit: color_distance_limit,
          driver: driver,
          screenshot_format: Screenshot.screenshot_format,
          capybara_screenshot_options: Screenshot.capybara_screenshot_options,
          shift_distance_limit: shift_distance_limit,
          skip_area: skip_area,
          stability_time_limit: Screenshot.stability_time_limit,
          tolerance: tolerance || ((driver == :vips) ? 0.001 : nil),
          wait: Capybara.default_max_wait_time
        }
      end
    end
  end
end
