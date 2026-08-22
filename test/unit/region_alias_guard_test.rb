# frozen_string_literal: true

require "test_helper"
require "snap_diff/region"
require "snap_diff/area_calculator"

# ADR-008 step 3 guards: Region's home is SnapDiff::Region, but user
# configs build skip_area entries with top-level `Region.new(...)` and
# feature-detect with `defined?(Region)`. The top-level name must stay an
# EAGER same-object alias -- not a copy, not a lazy shim.
class RegionAliasGuardTest < ActiveSupport::TestCase
  test "top-level Region is the exact same object as SnapDiff::Region" do
    assert_same SnapDiff::Region, ::Region,
      "expected ::Region and SnapDiff::Region to be the same class object"
  end

  test "defined?(Region) is truthy without any const_missing round-trip" do
    assert defined?(::Region), "defined?(::Region) must be truthy (eager alias, not a lazy shim)"
  end

  test "a top-level Region in skip_area survives SnapDiff internals' is_a? checks" do
    user_region = ::Region.new(5, 5, 10, 10)

    result = SnapDiff::AreaCalculator.new(nil, [user_region]).calculate_skip_area

    assert_equal [user_region], result
    assert_same user_region, result.first,
      "AreaCalculator's is_a?(Region) partition must keep the user's object as-is"
    assert result.first.is_a?(SnapDiff::Region)
  end
end
