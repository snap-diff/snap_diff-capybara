# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/area_calculator"

module Capybara::Screenshot::Diff
  class AreaCalculatorTest < ActiveSupport::TestCase
    test "skips non intersected skip areas and crop area" do
      skip_area = [[0, 0, 100, 100], [200, 200, 100, 100]]
      crop_area = [100, 100, 100, 100]
      calculator = AreaCalculator.new(crop_area, skip_area)

      assert_equal [], calculator.calculate_skip_area
    end

    test "skip area accepts region" do
      skip_area = [Region.new(0, 0, 100, 100)]
      crop_area = Region.new(0, 0, 200, 200)
      calculator = AreaCalculator.new(crop_area, skip_area)

      assert_equal [Region.new(0, 0, 100, 100)], calculator.calculate_skip_area
    end
  end
end
