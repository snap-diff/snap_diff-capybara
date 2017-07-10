require 'capybara/screenshot/diff/version'
require 'capybara/screenshot/diff/image_compare'
require 'capybara/screenshot/diff/capybara_setup'

module Capybara
  module Screenshot
    mattr_accessor :add_driver_path
    mattr_accessor :add_os_path
    mattr_accessor :blur_active_element
    mattr_accessor :enabled
    mattr_accessor :screenshot_root
    mattr_accessor :stability_time_limit
    mattr_accessor :window_size

    def self.active?
      enabled || (enabled.nil? && Diff.enabled)
    end

    # Module to track screen shot changes
    module Diff
      mattr_accessor :color_distance_limit
      mattr_accessor(:enabled) { true }
    end
  end
end
