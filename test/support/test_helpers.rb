# frozen_string_literal: true

require "support/test_doubles"

module TestHelpers
  include Capybara::Screenshot::Diff::TestDoubles
  # Common assertions for image comparison tests
  module Assertions
    # Asserts that a dimension check was called a specific number of times
    # @param driver [Object] The test driver object
    # @param times [Integer] The expected number of calls (default: 1)
    def assert_dimension_check_called(driver, times = 1)
      assert_equal times, driver.dimension_check_calls.size,
        "Expected dimension check to be called #{times} time(s)"
    end

    # Asserts that a pixel check was called a specific number of times
    # @param driver [Object] The test driver object
    # @param times [Integer] The expected number of calls (default: 1)
    def assert_pixel_check_called(driver, times = 1)
      assert_equal times, driver.pixel_check_calls.size,
        "Expected pixel check to be called #{times} time(s)"
    end

    # Asserts that a difference region check was called a specific number of times
    # @param driver [Object] The test driver object
    # @param times [Integer] The expected number of calls (default: 1)
    def assert_difference_region_called(driver, times = 1)
      assert_equal times, driver.difference_region_calls.size,
        "Expected difference region check to be called #{times} time(s)"
    end
  end

  # Common setup methods for test drivers
  module DriverSetup
    # Sets up driver results for testing
    # @param driver [Object] The test driver object
    # @param same_dimension [Boolean] Whether dimensions match (default: true)
    # @param same_pixels [Boolean, nil] Whether pixels match (default: nil for no change)
    # @param difference_region [Object, nil] The difference region result (default: nil)
    def setup_driver_results(driver, same_dimension: true, same_pixels: nil, difference_region: nil)
      driver.same_dimension_result = same_dimension
      driver.same_pixels_result = same_pixels unless same_pixels.nil?
      driver.difference_region_result = difference_region if difference_region
    end
  end

  # Common test data generators
  module TestData
    # Creates a test driver with the given options
    # @param is_vips [Boolean] Whether to create a VIPS driver (default: false)
    # @param images [Array, nil] Images to return from load_images (default: nil)
    # @return [TestDoubles::TestDriver] A test driver object
    def create_test_driver(is_vips: false, images: nil)
      Capybara::Screenshot::Diff::TestDoubles::TestDriver.new(is_vips, images)
    end
  end
end
