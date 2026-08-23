# frozen_string_literal: true

require "test_helper"
require "support/driver_coverage"

class DriverCoverageTest < ActiveSupport::TestCase
  test "#banner lists detected drivers" do
    assert_equal "[capybara-screenshot-diff] drivers detected: chunky_png, vips",
      DriverCoverage.banner(%i[chunky_png vips])
  end

  test "#banner calls out unavailable drivers" do
    assert_equal "[capybara-screenshot-diff] drivers detected: chunky_png | unavailable: vips",
      DriverCoverage.banner(%i[chunky_png])
  end

  test "#missing_for_ci returns nothing when CI is unset" do
    assert_empty DriverCoverage.missing_for_ci(%i[chunky_png], ci: nil)
  end

  test "#missing_for_ci returns nothing when CI is blank" do
    assert_empty DriverCoverage.missing_for_ci(%i[chunky_png vips], ci: "")
  end

  test "#missing_for_ci returns nothing in CI when both drivers are available" do
    assert_empty DriverCoverage.missing_for_ci(%i[chunky_png vips], ci: "true")
  end

  test "#missing_for_ci flags vips missing in CI" do
    assert_equal [:vips], DriverCoverage.missing_for_ci(%i[chunky_png], ci: "true")
  end

  test "#missing_for_ci flags chunky_png missing in CI" do
    assert_equal [:chunky_png], DriverCoverage.missing_for_ci(%i[vips], ci: "true")
  end

  test "#missing_for_ci honors an explicit exclude override" do
    assert_empty DriverCoverage.missing_for_ci(%i[chunky_png], ci: "true", exclude: [:vips])
  end
end
