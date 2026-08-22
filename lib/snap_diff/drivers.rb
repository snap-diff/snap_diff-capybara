# frozen_string_literal: true

module SnapDiff
  # Compare two images and determine if they are equal, different, or within some comparison
  # range considering color values and difference area size.
  module Drivers
    def self.for(driver_options = {})
      driver_option = driver_options.is_a?(Hash) ? driver_options.fetch(:driver, :chunky_png) : driver_options
      return driver_option unless driver_option.is_a?(Symbol)

      Utils.find_driver_class_for(driver_option).new
    end
  end
end
