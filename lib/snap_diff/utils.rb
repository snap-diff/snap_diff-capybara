# frozen_string_literal: true

require "snap_diff/drivers"

module SnapDiff
  module Utils
    # Detection itself lives on Drivers now (its canonical home -- so that
    # `require "snap_diff/drivers"` standalone can answer .available); this
    # keeps the documented Utils name working. One-way: Drivers never calls
    # back here at load time, so requiring either file first is safe.
    def self.detect_available_drivers
      Drivers.detect_available
    end

    def self.find_driver_class_for(driver)
      driver = Drivers.available.first if driver == :auto

      Drivers.loaded[driver] ||=
        case driver
        when :chunky_png
          require "snap_diff/drivers/chunky_png_driver"
          SnapDiff::Drivers::ChunkyPNGDriver
        when :vips
          require "snap_diff/drivers/vips_driver"
          SnapDiff::Drivers::VipsDriver
        else
          fail "Wrong adapter #{driver.inspect}. Available adapters: #{Drivers.available.inspect}"
        end
    end
  end
end
