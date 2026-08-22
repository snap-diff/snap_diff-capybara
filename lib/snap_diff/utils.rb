# frozen_string_literal: true

module SnapDiff
  module Utils
    def self.detect_available_drivers
      result = []
      begin
        result << :vips if defined?(Vips) || require("vips")
      rescue LoadError
        # vips not present
        Object.send(:remove_const, :Vips) if defined?(Vips)
      end
      begin
        result << :chunky_png if defined?(ChunkyPNG) || require("chunky_png")
      rescue LoadError
        # chunky_png not present
        Object.send(:remove_const, :ChunkyPNG) if defined?(ChunkyPNG)
      end
      result
    end

    def self.find_driver_class_for(driver)
      driver = Capybara::Screenshot::Diff::AVAILABLE_DRIVERS.first if driver == :auto

      Capybara::Screenshot::Diff::LOADED_DRIVERS[driver] ||=
        case driver
        when :chunky_png
          require "snap_diff/drivers/chunky_png_driver"
          SnapDiff::Drivers::ChunkyPNGDriver
        when :vips
          require "snap_diff/drivers/vips_driver"
          SnapDiff::Drivers::VipsDriver
        else
          fail "Wrong adapter #{driver.inspect}. Available adapters: #{Capybara::Screenshot::Diff::AVAILABLE_DRIVERS.inspect}"
        end
    end
  end
end
