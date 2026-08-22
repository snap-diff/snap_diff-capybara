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

    # Canonical driver-class cache (ADR-008 step 5b, ex
    # Capybara::Screenshot::Diff::LOADED_DRIVERS): driver name => driver
    # class, filled lazily by Utils.find_driver_class_for. Mutated in
    # place -- including by user registration through the legacy constant,
    # which legacy_shims pins as an EAGER same-object alias of this hash
    # (a lazy copy would silently drop such registrations).
    def self.loaded
      @loaded ||= {}
    end

    # Canonical read API for the detected-drivers list. The value itself
    # stays on Capybara::Screenshot::Diff::AVAILABLE_DRIVERS (assigned in
    # config_legacy.rb at load time, exactly when detection historically
    # ran); this reads it live rather than caching, because that constant
    # is the published stubbing point (image_compare_test stubs it to []
    # to exercise the no-drivers error path).
    def self.available
      Capybara::Screenshot::Diff::AVAILABLE_DRIVERS
    end
  end
end
