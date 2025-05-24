# frozen_string_literal: true

require "test_helper"
require_relative "test_doubles"

module Capybara
  module Screenshot
    module Diff
      class ImagePreprocessorTest < ActionDispatch::IntegrationTest
        include CapybaraScreenshotDiff::DSLStub
        include TestDoubles

        def setup
          @test_images = [:base_image, :new_image]
        end

        test "when no preprocessing options are provided then returns original images unchanged" do
          # Setup
          driver = TestDriver.new(false)
          options = {}

          # Action
          preprocessor = ImagePreprocessor.new(driver, options)
          result = preprocessor.call(@test_images)

          # Verify
          assert_equal @test_images, result
          assert_empty driver.add_black_box_calls
          assert_empty driver.filter_calls
        end

        test "when skip_area is specified then applies black box to that region" do
          # Setup
          driver = TestDriver.new(false)
          skip_area = [{x: 10, y: 20, width: 30, height: 40}]
          options = {skip_area: skip_area}

          # Action
          preprocessor = ImagePreprocessor.new(driver, options)
          result = preprocessor.call(@test_images)

          # Verify
          assert_equal %w[processed_base_image processed_new_image], result

          assert_equal 2, driver.add_black_box_calls.size

          first_call = driver.add_black_box_calls[0]
          second_call = driver.add_black_box_calls[1]

          assert_equal skip_area.first, first_call[:region]
          assert_equal skip_area.first, second_call[:region]
          assert_equal :base_image, first_call[:image]
          assert_equal :new_image, second_call[:image]
        end

        test "when median filter is specified with VipsDriver then applies filter to images" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)

          # Setup
          driver = TestDriver.new(true) # true = is a VipsDriver
          window_size = 3
          options = {median_filter_window_size: window_size}

          # Action
          preprocessor = ImagePreprocessor.new(driver, options)
          result = preprocessor.call(@test_images)

          # Verify
          assert_equal ["filtered_base_image", "filtered_new_image"], result

          assert_equal 2, driver.filter_calls.size

          first_call = driver.filter_calls[0]
          second_call = driver.filter_calls[1]

          assert_equal window_size, first_call[:size]
          assert_equal window_size, second_call[:size]
          assert_equal :base_image, first_call[:image]
          assert_equal :new_image, second_call[:image]
        end

        test "when median filter is specified with non-VipsDriver then issues warning and returns original images" do
          # Setup
          driver = TestDriver.new(false) # false = is not a VipsDriver
          window_size = 3
          options = {
            median_filter_window_size: window_size,
            image_path: "some/path.png"
          }

          # Set up a warning expectation
          expected_warning = /Median filter has been skipped for.*because it is not supported/

          # Action with warning capture
          preprocessor = ImagePreprocessor.new(driver, options)

          warning_output = capture_io do
            result = preprocessor.call(@test_images)

            # Verify images unchanged
            assert_equal @test_images, result
            assert_empty driver.filter_calls
          end

          # Verify warning
          assert_match expected_warning, warning_output.join
        end
      end
    end
  end
end
