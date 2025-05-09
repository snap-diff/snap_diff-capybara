# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      # Loads and preprocesses images for comparison
      #
      # This class is responsible for loading images and creating a Comparison object.
      # It coordinates with the ImagePreprocessor to apply any necessary filters
      # before creating the comparison. This follows the Single Responsibility Principle
      # by focusing solely on loading and assembling the comparison.
      class ComparisonLoader
        def initialize(driver)
          @driver = driver
        end

        # Load images and create a comparison object
        # @param [String] base_path the path to the base image
        # @param [String] new_path the path to the new image
        # @param [Hash] options options for the comparison
        # @return [Comparison] the comparison object
        def call(base_path, new_path, options = {})
          # Load the raw images
          images = @driver.load_images(base_path, new_path)

          # Create a preliminary comparison with raw images
          # This is used for enhanced preprocessing that needs context
          Comparison.new(images[1], images[0], options, @driver, new_path, base_path)
        end
      end
    end
  end
end
