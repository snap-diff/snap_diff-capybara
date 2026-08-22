# frozen_string_literal: true

module SnapDiff
  # Shared default behavior for image-processing drivers.
  #
  # Replaces the old +Capybara::Screenshot::Diff::Drivers::BaseDriver+
  # superclass (ADR-004 v2 step 4): concrete drivers +include Driver+
  # instead of inheriting. Method names are intentionally unchanged from
  # v1 — see dissent #4 in the v2 architecture design.
  module Driver
    PNG_EXTENSION = ".png"

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
