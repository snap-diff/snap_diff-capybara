# frozen_string_literal: true

require "snap_diff/drivers"
require "snap_diff/removal"

module SnapDiff
  module Utils
    # THE selection funnel. Every surface that picks a driver ends up here --
    # `driver: :chunky_png` per comparison, `SnapDiff.config.driver =`, the
    # legacy `Diff.driver =` (a delegator onto the same storage), and `:auto`
    # -- so this is the one place the chunky_png removal has to be announced
    # from. Warned before the registry lookup, not inside it: the cache is a
    # `||=`, so a hook there would fire only for the first comparison of a
    # process that happened to miss.
    CHUNKY_PNG_REMOVED =
      "The chunky_png driver is REMOVED in 2.1, when libvips (the `ruby-vips` gem) becomes " \
      "required. Install ruby-vips and drop `driver: :chunky_png`. See docs/drivers.md."

    # The case that matters most: nobody asked for this driver, so the
    # warning has to say why they are on it.
    CHUNKY_PNG_AUTO_REMOVED =
      "`driver: :auto` selected chunky_png because libvips is not available in this process. " \
      "The chunky_png driver is REMOVED in 2.1, when libvips (the `ruby-vips` gem) becomes " \
      "required -- install it now, or this setup stops comparing on 2.1. See docs/drivers.md."

    # Detection itself lives on Drivers now (its canonical home -- so that
    # `require "snap_diff/drivers"` standalone can answer .available); this
    # keeps the documented Utils name working. One-way: Drivers never calls
    # back here at load time, so requiring either file first is safe.
    def self.detect_available_drivers
      Drivers.detect_available
    end

    def self.find_driver_class_for(driver)
      if driver == :auto
        # Drivers::AVAILABLE_DRIVERS, not Drivers.available: same value and
        # the same stubbing point, without the gem tripping .available's own
        # removal warning on every comparison.
        driver = Drivers::AVAILABLE_DRIVERS.first
        Removal.warn_once(:chunky_png_auto, CHUNKY_PNG_AUTO_REMOVED) if driver == :chunky_png
      elsif driver == :chunky_png
        Removal.warn_once(:chunky_png, CHUNKY_PNG_REMOVED)
      end

      Drivers.registry[driver] ||=
        case driver
        when :chunky_png
          require "snap_diff/drivers/chunky_png_driver"
          SnapDiff::Drivers::ChunkyPNGDriver
        when :vips
          require "snap_diff/drivers/vips_driver"
          SnapDiff::Drivers::VipsDriver
        else
          fail "Wrong adapter #{driver.inspect}. Available adapters: #{Drivers::AVAILABLE_DRIVERS.inspect}"
        end
    end
  end
end
