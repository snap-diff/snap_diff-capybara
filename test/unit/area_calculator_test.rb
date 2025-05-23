# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/area_calculator"

module Capybara
  module Screenshot
    module Diff
      class AreaCalculatorTest < ActiveSupport::TestCase
        class CalculateSkipAreaTest < self
          test "#calculate_skip_area returns empty array when no skip areas overlap with crop area" do
            skip_area = [[0, 0, 100, 100], [200, 200, 100, 100]]
            crop_area = [100, 100, 100, 100]
            calculator = AreaCalculator.new(crop_area, skip_area)

            result = calculator.calculate_skip_area

            assert_empty result
          end

          test "#calculate_skip_area returns intersecting regions when skip areas overlap with crop area" do
            skip_area = [Region.new(50, 50, 150, 150)]
            crop_area = Region.new(0, 0, 200, 200)
            calculator = AreaCalculator.new(crop_area, skip_area)

            result = calculator.calculate_skip_area

            assert_equal [Region.new(50, 50, 150, 150)], result
          end
        end

        class InitializationTest < self
          test "#initialize handles Region objects for skip areas correctly" do
            skip_area = [Region.new(0, 0, 100, 100)]
            crop_area = Region.new(0, 0, 200, 200)

            calculator = AreaCalculator.new(crop_area, skip_area)

            assert_equal [Region.new(0, 0, 100, 100)], calculator.calculate_skip_area
          end

          test "#initialize converts array coordinates to Region objects" do
            skip_area = [[0, 0, 100, 100]]
            crop_area = [0, 0, 200, 200]

            calculator = AreaCalculator.new(crop_area, skip_area)
            result = calculator.calculate_skip_area

            assert_equal 1, result.size
            assert_kind_of Region, result.first
            assert_equal [0, 0, 100, 100],
              [result.first.left, result.first.top, result.first.right, result.first.bottom]
          end
        end

        class EdgeCaseTest < self
          test "#calculate_skip_area returns empty array when skip_areas is empty" do
            calculator = AreaCalculator.new([0, 0, 100, 100], [])

            result = calculator.calculate_skip_area

            assert_empty result
          end

          test "#calculate_skip_area returns nil when skip_areas is not provided (nil)" do
            calculator = AreaCalculator.new([0, 0, 100, 100], nil)

            result = calculator.calculate_skip_area

            assert_nil result
          end
        end
      end
    end
  end
end
