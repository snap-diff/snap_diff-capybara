# frozen_string_literal: true

require "test_helper"
require "support/test_doubles"
require "support/test_helpers"

module Capybara
  module Screenshot
    module Diff
      class ImagePreprocessorTest < ActiveSupport::TestCase
        include CapybaraScreenshotDiff::DSLStub
        include TestHelpers

        def setup
          super
          @test_images = [:base_image, :new_image]
          @driver = create_test_driver
        end

        test "#call returns original images when no preprocessing options are provided" do
          preprocessor = ImagePreprocessor.new(@driver, {})

          result = preprocessor.call(@test_images)

          assert_equal @test_images, result
          assert_empty @driver.add_black_box_calls
          assert_empty @driver.filter_calls
        end

        test "#call applies black box to skip areas when skip_area option is provided" do
          skip_area = [{x: 10, y: 20, width: 30, height: 40}]
          preprocessor = ImagePreprocessor.new(@driver, skip_area: skip_area)

          result = preprocessor.call(@test_images)

          assert_equal %w[processed_base_image processed_new_image], result
          assert_equal 2, @driver.add_black_box_calls.size

          first_call = @driver.add_black_box_calls[0]
          second_call = @driver.add_black_box_calls[1]

          assert_equal skip_area.first, first_call[:region]
          assert_equal skip_area.first, second_call[:region]
          assert_equal :base_image, first_call[:image]
          assert_equal :new_image, second_call[:image]
        end

        test "#call applies median filter when VipsDriver is available and median_filter_window_size is specified" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)

          @driver = create_test_driver(is_vips: true)
          window_size = 3
          options = {median_filter_window_size: window_size}
          preprocessor = ImagePreprocessor.new(@driver, options)

          result = preprocessor.call(@test_images)

          assert_equal ["filtered_base_image", "filtered_new_image"], result
          assert_equal 2, @driver.filter_calls.size

          first_call = @driver.filter_calls[0]
          second_call = @driver.filter_calls[1]

          assert_equal window_size, first_call[:size]
          assert_equal window_size, second_call[:size]
          assert_equal :base_image, first_call[:image]
          assert_equal :new_image, second_call[:image]
        end

        test "call warns and skips median filter when VipsDriver is not available" do
          window_size = 3
          options = {
            median_filter_window_size: window_size,
            image_path: "some/path.png"
          }

          expected_warning = /Median filter has been skipped for.*because it is not supported/

          warning_output = capture_io do
            preprocessor = ImagePreprocessor.new(@driver, options)
            result = preprocessor.call(@test_images)

            assert_equal @test_images, result
            assert_empty @driver.filter_calls
          end

          assert_match expected_warning, warning_output.join
        end
      end
    end
  end
end
