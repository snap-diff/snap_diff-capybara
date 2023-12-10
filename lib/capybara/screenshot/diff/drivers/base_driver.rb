# frozen_string_literal: true

require "chunky_png"
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

          # Checks if the given image fits within the specified dimensions.
          #
          # @param dimensions [Array<Integer>] An array containing the width and height to check against.
          # @param image [ChunkyPNG::Image] The image to check.
          #
          # @return [Boolean] Returns `true` if the image's width and height are both less than the corresponding dimensions, and `false` otherwise.
          def inscribed?(dimensions, image)
            width_for(image) < dimensions[0] || height_for(image) < dimensions[1]
          end
        end
      end
    end
  end
end
