# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      LOADED_DRIVERS = {}

      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      class ImageCompare < SimpleDelegator
        attr_reader :driver, :driver_options

        def initialize(new_file_name, old_file_name = nil, **driver_options)
          @driver_options = driver_options

          driver_klass = find_driver_class_for(driver_options.fetch(:driver, :chunky_png))
          @driver = driver_klass.new(new_file_name, old_file_name, **driver_options)

          super(@driver)
        end

        private

        def find_driver_class_for(driver)
          driver = AVAILABLE_DRIVERS.first if driver == :auto

          LOADED_DRIVERS[driver] ||=
            case driver
            when :chunky_png
              require "capybara/screenshot/diff/drivers/chunky_png_driver"
              Drivers::ChunkyPNGDriver
            when :vips
              require "capybara/screenshot/diff/drivers/vips_driver"
              Drivers::VipsDriver
            else
              fail "Wrong adapter #{driver.inspect}. Available adapters: #{AVAILABLE_DRIVERS.inspect}"
            end
        end
      end
    end
  end
end
