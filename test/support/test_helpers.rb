# frozen_string_literal: true

require "support/test_doubles"

module TestHelpers
  include Capybara::Screenshot::Diff::TestDoubles

  # Common assertions for image comparison tests
  module Assertions
    # Asserts that a driver check was called a specific number of times
    # @param driver [Object] The test driver object
    # @param check_type [Symbol] :dimension_check, :pixel_check, or :difference_region
    # @param times [Integer] The expected number of calls (default: 1)
    def assert_driver_check_called(driver, check_type, times = 1)
      calls = driver.public_send(:"#{check_type}_calls")
      assert_equal times, calls.size,
        "Expected #{check_type} to be called #{times} time(s), was called #{calls.size}"
    end

    # Convenience aliases for backward compatibility
    def assert_dimension_check_called(driver, times = 1) = assert_driver_check_called(driver, :dimension_check, times)
    def assert_pixel_check_called(driver, times = 1) = assert_driver_check_called(driver, :pixel_check, times)
    def assert_difference_region_called(driver, times = 1) = assert_driver_check_called(driver, :difference_region, times)
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
