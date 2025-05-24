# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      module TestDoubles
        # Test double for file paths with configurable size and existence
        class TestPath
          attr_reader :size_value

          # Initialize a path with a size value and existence flag
          # @param size_value [Integer] The size of the file
          # @param exists [Boolean] Whether the file exists, defaults to true
          def initialize(size_value, exists = true)
            @size_value = size_value
            @exists = exists
          end

          def size
            @size_value
          end

          def exist?
            @exists
          end
        end

        # Test double for image drivers with configurable behavior
        class TestDriver
          attr_reader :add_black_box_calls, :filter_calls, :dimension_check_calls, :pixel_check_calls, :difference_region_calls, :load_images_called, :load_images_args
          attr_accessor :same_dimension_result, :same_pixels_result, :difference_region_result, :images_to_return

          # Initializes a new TestDriver
          # @param is_vips_driver [Boolean] whether this driver should behave like a VipsDriver
          # @param images_to_return [Array] images to return from load_images method
          def initialize(is_vips_driver = false, images_to_return = nil)
            @is_vips_driver = is_vips_driver
            @images_to_return = images_to_return || [:base_image, :new_image]
            @add_black_box_calls = []
            @filter_calls = []
            @dimension_check_calls = []
            @pixel_check_calls = []
            @difference_region_calls = []
            @load_images_called = false
            @load_images_args = nil
            @same_dimension_result = true
            @same_pixels_result = true
            @difference_region_result = nil
          end

          def is_a?(klass)
            return @is_vips_driver if klass == Drivers::VipsDriver
            super
          end

          def add_black_box(image, region)
            @add_black_box_calls << {image: image, region: region}
            "processed_#{image}"
          end

          def filter_image_with_median(image, size)
            @filter_calls << {image: image, size: size}
            # Return the filtered image, converting to the expected format
            "filtered_#{image}"
          end

          def same_dimension?(comparison)
            @dimension_check_calls << comparison
            @same_dimension_result
          end

          def same_pixels?(comparison)
            @pixel_check_calls << comparison
            @same_pixels_result
          end

          def find_difference_region(comparison)
            @difference_region_calls << comparison
            @difference_region_result
          end

          def load_images(base_path, new_path)
            @load_images_called = true
            @load_images_args = [base_path, new_path]
            @images_to_return
          end

          def supports?(...)
            @is_vips_driver
          end

          # Return Object to avoid infinite recursion
          def class
            Object
          end
        end

        # Test double for image preprocessors
        class TestPreprocessor
          attr_reader :call_called, :call_args, :process_comparison_called, :process_comparison_args, :processed_images

          def initialize(processed_images)
            @processed_images = processed_images
            @call_called = false
            @call_args = nil
            @process_comparison_called = false
            @process_comparison_args = nil
          end

          def call(images)
            @call_called = true
            @call_args = images
            processed_images
          end

          # Process a comparison object directly
          # Mirrors the implementation in ImagePreprocessor
          def process_comparison(comparison)
            @process_comparison_called = true
            @process_comparison_args = comparison
            comparison
          end
        end

        # Test double for difference results
        class TestDifference
          attr_reader :different_value

          def initialize(different_value)
            @different_value = different_value
          end

          def different?
            @different_value
          end
        end

        # Simple test double for comparison objects
        class TestComparison
          attr_reader :new_image, :base_image, :options, :driver
          attr_accessor :new_image_path, :base_image_path

          def initialize(options = {})
            @new_image = options[:new_image]
            @base_image = options[:base_image]
            @options = options[:options] || {}
            @driver = options[:driver]
            @new_image_path = options[:new_image_path] || options[:image_path]
            @base_image_path = options[:base_image_path]
          end
        end
      end
    end
  end
end
