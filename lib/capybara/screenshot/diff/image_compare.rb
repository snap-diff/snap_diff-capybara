# frozen_string_literal: true

require_relative './drivers/chunky_png_driver'
require_relative './drivers/vips_driver'

module Capybara
  module Screenshot
    module Diff
      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      class ImageCompare < SimpleDelegator
        attr_reader :driver, :driver_options

        def initialize(new_file_name, old_file_name = nil, **driver_options)
          @driver_options = driver_options

          driver_klass = find_driver_class_for(driver_options.fetch(:driver) { :chunky_png })
          @driver = driver_klass.new(new_file_name, old_file_name, **driver_options)

          super(@driver)
        end

        private

        def find_driver_class_for(driver)
          case driver
          when :vips
            Drivers::VipsDriver
          when :chunky_png
            Drivers::ChunkyPNGDriver
          else
            fail "Wrong adapter #{driver.inspect}. Available adapter: :vips or :chunky_png"
          end
        end
      end
    end
  end
end
