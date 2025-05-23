# frozen_string_literal: true

require "test_helper"
require "support/test_doubles"
require "capybara/screenshot/diff/difference_finder"

module Capybara
  module Screenshot
    module Diff
      class DifferenceFinderTest < ActiveSupport::TestCase
        include CapybaraScreenshotDiff::DSLStub
        include TestDoubles

        class InitializationTest < self
          setup do
            @base_path = TestDoubles::TestPath.new(12345)
            @new_path = TestDoubles::TestPath.new(54321)
            @driver = TestDoubles::TestDriver.new(false)
            setup_test_comparison
          end

          test "#initialize sets driver and options correctly" do
            driver = TestDoubles::TestDriver.new
            options = {tolerance: 0.05}

            finder = DifferenceFinder.new(driver, options)

            assert_equal driver, finder.driver
            assert_equal options, finder.options
          end
        end

        class QuickModeTest < self
          setup do
            @base_path = TestDoubles::TestPath.new(12345)
            @new_path = TestDoubles::TestPath.new(54321)
            @driver = TestDoubles::TestDriver.new(false)
            setup_test_comparison
            @finder = create_finder
          end

          test "#call in quick_mode returns true with difference when images match exactly" do
            setup_driver_results(@driver, same_dimension: true, same_pixels: true)

            result, difference = @finder.call(@comparison, quick_mode: true)

            assert result, "Expected call to return true"
            refute_nil difference, "Expected a difference object"
            assert_dimension_check_called(@driver)
            assert_pixel_check_called(@driver)
          end

          test "#call in quick_mode with tolerance returns true when difference is within tolerance" do
            test_difference = TestDifference.new(false) # Not different (within tolerance)
            setup_driver_results(@driver, same_dimension: true, same_pixels: false, difference_region: test_difference)

            finder = create_finder(tolerance: 0.01)
            result, difference = finder.call(@comparison, quick_mode: true)

            assert result, "Expected call to return true when within tolerance"
            assert_equal test_difference, difference
          end

          test "#call in quick_mode returns false without difference when pixels differ beyond tolerance" do
            setup_driver_results(@driver, same_dimension: true, same_pixels: false)

            result, difference = @finder.call(@comparison, quick_mode: true)

            refute result, "Expected call to return false when pixels differ"
            assert_nil difference, "Expected no difference object in quick mode"
            assert_dimension_check_called(@driver)
            assert_pixel_check_called(@driver)
            assert_difference_region_called(@driver, 0)
          end
        end

        class FullModeTest < self
          setup do
            @base_path = TestDoubles::TestPath.new(12345)
            @new_path = TestDoubles::TestPath.new(54321)
            @driver = TestDoubles::TestDriver.new(false)
            setup_test_comparison
            @finder = create_finder
          end

          test "#call in full_mode returns failed difference when image dimensions differ" do
            setup_driver_results(@driver, same_dimension: false)

            result = @finder.call(@comparison, quick_mode: false)

            assert_instance_of Difference, result
            assert result.failed?, "Expected failed result when dimensions differ"
            assert_dimension_check_called(@driver)
            assert_pixel_check_called(@driver, 0)
          end

          test "#call in full_mode returns equal result when images match exactly" do
            setup_driver_results(@driver, same_dimension: true, same_pixels: true)

            result = @finder.call(@comparison, quick_mode: false)

            assert_instance_of Difference, result
            assert result.equal?, "Expected equal result when pixels match"
            assert_dimension_check_called(@driver)
            assert_pixel_check_called(@driver)
          end

          test "#call in full_mode returns difference when pixels differ beyond tolerance" do
            test_difference = TestDifference.new(true)
            setup_driver_results(@driver, same_dimension: true, same_pixels: false, difference_region: test_difference)

            result = @finder.call(@comparison, quick_mode: false)

            assert_equal test_difference, result
            assert_difference_region_called(@driver)
          end
        end

        private

        def setup_test_comparison
          @comparison = TestDoubles::TestComparison.new
          @comparison.base_image_path = @base_path
          @comparison.new_image_path = @new_path
        end

        def create_finder(options = {})
          DifferenceFinder.new(@driver, options)
        end
      end
    end
  end
end
