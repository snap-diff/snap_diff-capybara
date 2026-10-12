# frozen_string_literal: true

require "test_helper"
require "snap_diff/comparison_result"

class DifferenceTest < ActiveSupport::TestCase
  setup do
    @difference = SnapDiff::ComparisonResult.new(nil, {}, nil, {different_dimensions: []})
  end

  test "#different? returns true when images have different dimensions" do
    assert_predicate @difference, :different?
  end

  test "#failed? returns true when images have different dimensions" do
    assert_predicate @difference, :failed?
  end

  test "#inspect is a one-line summary with the difference metrics" do
    line = @difference.inspect

    assert_includes line, "different=true"
    assert_includes line, "failed_by="
    assert_includes line, "area_size=0"
    assert_includes line, "difference_level="
    assert_not_includes line, "\n"
  end

  # build_null freezes its result, so every reader must work on a frozen
  # instance.
  test "a frozen null result answers its readers" do
    null = SnapDiff::ComparisonResult.build_null(nil, nil, nil, {different_dimensions: true})

    assert_predicate null, :frozen?
    assert_equal 0, null.region_area_size
    assert_equal 0, null.to_h[:area_size]
    assert_includes null.inspect, "area_size=0"
  end
end
