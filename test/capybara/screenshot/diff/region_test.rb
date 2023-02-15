# frozen_string_literal: true

require "test_helper"

module Capybara::Screenshot::Diff
  class RegionTest < ActiveSupport::TestCase
    test "move_by moves region coordinates" do
      region = Region.new(10, 10, 10, 10).move_by(-5, -5)

      assert_equal 5, region.x
      assert_equal 5, region.y
      assert_equal 10, region.width
      assert_equal 10, region.height
    end

    test "find_intersect" do
      crop = Region.new(5, 5, 10, 10)
      region = Region.new(10, 10, 20, 20).find_intersect_with(crop)

      assert_equal 10, region.x
      assert_equal 10, region.y
      assert_equal 5, region.width
      assert_equal 5, region.height
    end

    test "find_relative_intersect finds intersect and returns relative position" do
      crop = Region.new(5, 5, 10, 10)

      region = crop.find_relative_intersect(Region.new(0, 0, 20, 20))

      assert_equal 0, region.x
      assert_equal 0, region.y
      assert_equal 10, region.width
      assert_equal 10, region.height

      region = crop.find_relative_intersect(Region.new(10, 10, 20, 20))

      assert_equal 5, region.x
      assert_equal 5, region.y
      assert_equal 5, region.width
      assert_equal 5, region.height
    end

    test ".from_edge_coordinates returns nil for missed coordinates" do
      assert_nil Region.from_edge_coordinates(0, 0, nil, nil)
    end

    test ".from_edge_coordinates returns nil for bottom before top and right before left" do
      assert_nil Region.from_edge_coordinates(10, 10, 9, 11)
      assert_nil Region.from_edge_coordinates(10, 10, 11, 9)
    end

    test ".from_top_left_corner_coordinates returns nil for missed coordinates" do
      assert_nil Region.from_top_left_corner_coordinates(0, 0, nil, nil)
    end

    test ".from_top_left_corner_coordinates returns nil for negative width or height" do
      assert_nil Region.from_top_left_corner_coordinates(10, 10, -1, 11)
      assert_nil Region.from_top_left_corner_coordinates(10, 10, 11, -1)
    end
  end
end
