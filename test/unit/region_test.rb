# frozen_string_literal: true

require "test_helper"

module Capybara::Screenshot::Diff
  class RegionTest < ActiveSupport::TestCase
    test "#move_by updates region coordinates by specified deltas" do
      region = Region.new(10, 10, 10, 10).move_by(-5, -5)

      assert_equal 5, region.x
      assert_equal 5, region.y
      assert_equal 10, region.width
      assert_equal 10, region.height
    end

    test "#find_intersect_with returns intersection with another region" do
      crop = Region.new(5, 5, 10, 10)
      region = Region.new(10, 10, 20, 20).find_intersect_with(crop)

      assert_equal 10, region.x
      assert_equal 10, region.y
      assert_equal 5, region.width
      assert_equal 5, region.height
    end

    test "#find_relative_intersect returns intersection with relative coordinates" do
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

    test ".from_edge_coordinates returns nil when right or bottom is nil" do
      assert_nil Region.from_edge_coordinates(0, 0, nil, nil)
    end

    test ".from_edge_coordinates returns nil when region has zero or negative dimensions" do
      assert_nil Region.from_edge_coordinates(10, 10, 9, 11)
      assert_nil Region.from_edge_coordinates(10, 10, 11, 9)
    end

    test "#== returns true when comparing with an identical Region" do
      assert_equal Region.new(10, 10, 10, 10), Region.new(10, 10, 10, 10)
      assert_not_equal Region.new(10, 10, 10, 10), Region.new(10, 10, 10, 11)
    end

    test "#== returns true when comparing with equivalent Array of coordinates" do
      assert_equal Region.new(10, 10, 10, 10), [10, 10, 10, 10]
      assert_not_equal Region.new(10, 10, 10, 10), [10, 10, 10, 11]
    end
  end
end
