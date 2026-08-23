# frozen_string_literal: true

require "snap_diff/removal"

module SnapDiff
  # Shared default behavior for image-processing drivers.
  #
  # Replaces the old +Capybara::Screenshot::Diff::Drivers::BaseDriver+
  # superclass (ADR-004 v2 step 4): concrete drivers +include Driver+
  # instead of inheriting. Method names are intentionally unchanged from
  # v1 — see dissent #4 in the v2 architecture design.
  module Driver
    PNG_EXTENSION = ".png"

    # Including this mixin is what makes a custom driver a driver, so it is
    # where a custom-driver author can be told that 2.1 removes the whole
    # abstraction. Scoped to drivers that are NOT the gem's own two: both
    # bundled drivers include it themselves, and warning there would fire on
    # every plain vips setup -- about code the user does not own.
    def self.included(base)
      return if base.name.to_s.start_with?("SnapDiff::")

      Removal.warn_once(
        :driver_mixin,
        "`include SnapDiff::Driver` (in #{base.name || base.inspect}) is REMOVED in 2.1: the " \
        "driver abstraction goes away and libvips becomes the only backend, so custom drivers " \
        "stop working. There is no replacement -- see docs/drivers.md."
      )
    end

    def same_dimension?(comparison)
      dimension(comparison.base_image) == dimension(comparison.new_image)
    end

    def height_for(image)
      image.height
    end

    def width_for(image)
      image.width
    end

    def image_area_size(image)
      width_for(image) * height_for(image)
    end

    def dimension(image)
      [width_for(image), height_for(image)]
    end

    def supports?(feature)
      respond_to?(feature)
    end
  end
end
