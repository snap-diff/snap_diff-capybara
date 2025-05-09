# frozen_string_literal: true

require "test_helper"
require_relative "test_doubles"

module Capybara
  module Screenshot
    module Diff
      class DifferenceFinderTest < ActionDispatch::IntegrationTest
        include CapybaraScreenshotDiff::DSLStub
        include TestDoubles

        def setup
          @base_path = TestPath.new(12345)
          @new_path = TestPath.new(54321) # Different size
          @driver = TestDriver.new(false)

          # Create a test comparison with paths directly
          @comparison = TestComparison.new
          @comparison.base_image_path = @base_path
          @comparison.new_image_path = @new_path
        end

        def create_difference_factory
          lambda do |comparison, failed_by = nil|
            @factory_calls ||= []
            @factory_calls << {comparison: comparison, failed_by: failed_by}

            if failed_by
              :dimension_difference_result
            else
              :no_difference_result
            end
          end
        end

        test "when dimensions are the same and pixels are the same then returns true in quick mode" do
          # Setup
          @driver.same_dimension_result = true
          @driver.same_pixels_result = true

          # Action
          finder = DifferenceFinder.new(@driver, {})
          result, difference = finder.call(@comparison, quick_mode: true)

          # Verify
          assert result
          refute_nil difference
          assert_equal 1, @driver.dimension_check_calls.size
          assert_equal 1, @driver.pixel_check_calls.size
        end

        test "when dimensions differ then returns a difference with failed dimensions" do
          # Setup
          @driver.same_dimension_result = false

          # Action
          finder = DifferenceFinder.new(@driver, {})
          result = finder.call(@comparison, quick_mode: false)

          # Verify
          assert_instance_of Difference, result
          assert result.failed?
          assert_equal 1, @driver.dimension_check_calls.size
          assert_equal 0, @driver.pixel_check_calls.size
        end

        test "when pixels are the same then returns no difference" do
          # Setup
          @driver.same_dimension_result = true
          @driver.same_pixels_result = true

          # Action
          finder = DifferenceFinder.new(@driver, {})
          result = finder.call(@comparison, quick_mode: false)

          # Verify
          assert_instance_of Difference, result
          assert result.equal?
          assert_equal 1, @driver.dimension_check_calls.size
          assert_equal 1, @driver.pixel_check_calls.size
        end

        test "when pixels differ then checks difference region" do
          # Setup
          @driver.same_dimension_result = true
          @driver.same_pixels_result = false
          test_difference = TestDifference.new(true) # It is different
          @driver.difference_region_result = test_difference

          # Action
          finder = DifferenceFinder.new(@driver, {})
          result = finder.call(@comparison, quick_mode: false)

          # Verify
          assert_equal test_difference, result
          assert_equal 1, @driver.difference_region_calls.size
        end

        test "when in quick mode returns array with comparison result and difference" do
          # Setup
          @driver.same_dimension_result = true
          @driver.same_pixels_result = false
          test_difference = TestDifference.new(false) # Not different (within tolerance)
          @driver.difference_region_result = test_difference

          # Action
          finder = DifferenceFinder.new(@driver, {tolerance: 0.01})
          result, difference = finder.call(@comparison, quick_mode: true)

          # Verify
          assert result # Not different == true equality
          assert_equal test_difference, difference
        end

        test "when comparison has no tolerable options in quick mode, returns early" do
          # Setup
          @driver.same_dimension_result = true
          @driver.same_pixels_result = false

          # Action
          finder = DifferenceFinder.new(@driver, {})
          result, difference = finder.call(@comparison, quick_mode: true)

          # Verify
          refute result # Different == false equality
          assert_nil difference # Quick mode with no tolerance returns nil difference
          assert_equal 1, @driver.dimension_check_calls.size
          assert_equal 1, @driver.pixel_check_calls.size
          assert_equal 0, @driver.difference_region_calls.size # Should not process difference region
        end
      end
    end
  end
end
