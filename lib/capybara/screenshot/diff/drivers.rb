# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      module Drivers
        def self.for(driver_options = {})
          driver_option = driver_options.is_a?(Hash) ? driver_options.fetch(:driver, :chunky_png) : driver_options
          return driver_option unless driver_option.is_a?(Symbol)

          Utils.find_driver_class_for(driver_option).new
        end
      end
    end
  end
end
