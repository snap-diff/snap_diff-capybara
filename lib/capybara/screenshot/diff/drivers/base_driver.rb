# frozen_string_literal: true

require "capybara/screenshot/diff/difference"

module Capybara
  module Screenshot
    module Diff
      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      module Drivers
        class BaseDriver
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
    end
  end
end
