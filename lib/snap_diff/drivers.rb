# frozen_string_literal: true

module SnapDiff
  # Compare two images and determine if they are equal, different, or within some comparison
  # range considering color values and difference area size.
  module Drivers
    def self.for(driver_options = {})
      driver_option = driver_options.is_a?(Hash) ? driver_options.fetch(:driver, :chunky_png) : driver_options
      return driver_option unless driver_option.is_a?(Symbol)

      # Deferred: utils.rb requires THIS file at its top, so requiring it
      # back at load time makes Ruby shout "circular require considered
      # harmful" under $VERBOSE (which Rake::TestTask sets by default).
      # Nothing here needs Utils until this method runs.
      require "snap_diff/utils"
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

    # Which image drivers this process can actually load, in preference
    # order. Tries the gem first and falls back to `require`, cleaning up
    # the half-defined constant a failed native load leaves behind.
    def self.detect_available
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

    # Canonical home of the detected-drivers list (3.0 readiness: it used
    # to live only on Capybara::Screenshot::Diff::AVAILABLE_DRIVERS, so
    # `require "snap_diff/drivers"` alone left .available raising
    # NameError). Detection runs HERE, at this file's load, and the legacy
    # constant is now an eager same-object alias of this one.
    AVAILABLE_DRIVERS = detect_available.freeze

    # The driver classes are documented names (the legacy
    # `...::Drivers::VipsDriver` path is a same-object alias of this one), so
    # naming one has to work without a prior require. Autoload rather than
    # require: naming one must not cost every process the vips/chunky_png
    # load, and Utils.find_driver_class_for still requires them explicitly.
    #
    # Gated on AVAILABLE_DRIVERS, which is why these sit BELOW it. Declaring
    # them unconditionally made `const_defined?(:VipsDriver)` true on a box
    # without ruby-vips (neither driver gem is a runtime dependency), so the
    # documented v1 pattern `Diff.driver = :vips if defined?(...VipsDriver)`
    # took the branch and then blew up on const_get. v1.12.0 loaded
    # vips_driver.rb only from find_driver_class_for, so `defined?` was nil
    # there -- this keeps that.
    autoload :ChunkyPNGDriver, "snap_diff/drivers/chunky_png_driver" if AVAILABLE_DRIVERS.include?(:chunky_png)
    autoload :VipsDriver, "snap_diff/drivers/vips_driver" if AVAILABLE_DRIVERS.include?(:vips)

    # Canonical read API for the list above. Reads the constant live rather
    # than caching, because the constant is the published stubbing point
    # (image_compare_test stubs it to [] to exercise the no-drivers error
    # path).
    def self.available
      AVAILABLE_DRIVERS
    end
  end
end
