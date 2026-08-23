# frozen_string_literal: true

require "test_helper"
require "minitest/stub_const"
require "snap_diff/drivers/chunky_png_driver"
if defined?(Vips)
  require "snap_diff/drivers/vips_driver"
elsif ENV["SCREENSHOT_DRIVER"] == "vips"
  raise 'Required `ruby-vips` gem or `vips` library is missing. Ensure "ruby-vips" gem and "vips" library is installed.'
end

class ImageCompareTest < ActiveSupport::TestCase
  include DSLStub

  test "#initialize creates instance with chunky_png driver by default" do
    comparison = make_comparison(:b)
    assert_kind_of SnapDiff::Drivers::ChunkyPNGDriver, comparison.driver
  end

  test "#initialize creates instance with explicit chunky_png driver" do
    comparison = make_comparison(:b, driver: :chunky_png)
    assert_kind_of SnapDiff::Drivers::ChunkyPNGDriver, comparison.driver
  end

  test "#initialize creates instance with vips driver when specified" do
    skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
    comparison = make_comparison(:b, driver: :vips)
    assert_kind_of SnapDiff::Drivers::VipsDriver, comparison.driver
  end

  test "#different? with vips driver generates annotated diff images" do
    skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
    comparison = make_comparison(:a, :b, driver: :vips)

    assert comparison.different?

    assert_same_images("a-and-b.diff.png", comparison.reporter.annotated_base_image_path)
    assert_same_images("b-and-a.diff.png", comparison.reporter.annotated_image_path)
  end

  test "#different? handles very long input filenames with vips driver" do
    skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
    filename = %w[this-0000000000000000000000000000000000000000000000000-path/is/extremely/
      long/and/if/the/directories/are/flattened/in/
      the_temporary_they_will_cause_the_filename_to_exceed_
      the_limit_on_most_unix_systems_which_nobody_wants.png].join
    comparison = make_comparison(:a, :b, destination: (Rails.root / filename), driver: :vips)

    assert comparison.different?
  end

  test "#initialize with vips driver respects tolerance option" do
    skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
    comp = make_comparison(:a, :b, driver: :vips, tolerance: 0.02)
    assert comp.quick_equal?
    assert_not comp.different?
  end

  test "#initialize with chunky_png driver respects tolerance option" do
    comp = make_comparison(:a, :b, driver: :chunky_png, tolerance: 0.02)
    assert comp.quick_equal?
    assert_not comp.different?
    assert_equal 0.02, comp.driver_options[:tolerance]
  end

  test "#initialize with dimensions creates valid comparison" do
    comp = make_comparison(:b, dimensions: [80, 80])
    assert comp.quick_equal?
    assert_not comp.different?
  end

  test "#initialize with :auto driver selects vips when available" do
    skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
    comparison = make_comparison(:b, driver: :auto)
    assert_kind_of SnapDiff::Drivers::VipsDriver, comparison.driver
  end

  test "#initialize with :auto driver raises error when no drivers available" do
    # Canonical stubbing point since the detected-drivers list moved to
    # SnapDiff::Drivers (2.1 readiness). The legacy
    # Capybara::Screenshot::Diff::AVAILABLE_DRIVERS is now an eager
    # same-object ALIAS of this constant, so stubbing the old name only
    # rebinds the alias and no longer reaches the core.
    SnapDiff::Drivers.stub_const(:AVAILABLE_DRIVERS, []) do
      assert_raise(RuntimeError) do
        comparison = make_comparison(:b, driver: :auto)
        assert comparison.quick_equal?
      end
    end
  end
end

# Guards the regression killed twice during ADR-004 review (migration-plan PR 5): skip_area
# masking must run at *comparison* time, against whatever base image is on disk (including a
# baseline checked out from VCS), not baked in at *capture* time. Capture-time masking would
# only ever touch the freshly-taken screenshot; a VCS-checked-out baseline predates that
# capture and would never get masked, so a masked new image compared against an unmasked
# baseline would still report a difference in the skip area.
#
# `make_comparison(:a, :c)` stands in for that scenario: `:a` plays the already-on-disk
# baseline (as if checked out from VCS), `:c` plays the freshly captured screenshot. The two
# fixtures are known to differ only within [11,3,48,20] (see ChunkyPNGDriverTest above).
class SkipAreaMasksVcsBaselineTest < ActiveSupport::TestCase
  include DSLStub

  test "#different? masks the VCS-checked-out baseline, not just the new screenshot" do
    skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)

    full_image_region = Region.from_edge_coordinates(0, 0, 80, 80)
    comparison = make_comparison(:a, :c, destination: "skip_area_vcs_baseline", driver: :vips, skip_area: [full_image_region])

    refute_predicate comparison, :different?
  end
end

class IntegrationRegressionTest < ActiveSupport::TestCase
  include DSLStub

  AVAILABLE_DRIVERS = [{}, {driver: :chunky_png}]

  test "identical images are quick_equal and not different across all drivers" do
    images = all_fixtures_images_names
    AVAILABLE_DRIVERS.each do |driver|
      Dir.chdir File.expand_path("../fixtures/images", __dir__) do
        images.each do |old_img|
          new_img = old_img
          comparison = make_comparison(old_img, new_img, **driver)
          assert(
            comparison.quick_equal?,
            "compare #{old_img} with #{new_img} with #{driver} driver should be quick_equal"
          )
          assert_not(
            comparison.different?,
            "compare #{old_img} with #{new_img} with #{driver} driver should not be different"
          )
        end
      end
    end
  end

  test "different images are not quick_equal and are marked as different" do
    images = all_fixtures_images_names

    AVAILABLE_DRIVERS.each do |driver|
      images.each do |image|
        other_images = images - [image]
        other_images.each do |different_image|
          comparison = make_comparison(image, different_image, **driver)
          assert_not(
            comparison.quick_equal?,
            "compare #{image.inspect} with #{different_image.inspect} using #{driver} driver should not be quick_equal"
          )
          assert(
            comparison.different?,
            "compare #{image.inspect} with #{different_image.inspect} using #{driver} driver should be different"
          )
        end
      end
    end
  end

  def all_fixtures_images_names
    %w[a a_cropped b c d portrait portrait_b]
  end
end

class ImageCompareRefactorTest < ActiveSupport::TestCase
  include DSLStub
  include TestHelpers

  # Test #quick_equal? method
  test "#quick_equal? returns true when comparing identical images" do
    comparison = make_comparison(:a, :a)
    assert_predicate comparison, :quick_equal?
  end

  test "#quick_equal? returns false when comparing different images" do
    comparison = make_comparison(:a, :b)
    refute_predicate comparison, :quick_equal?
  end

  test "#quick_equal? skips the expensive region scan when pixels differ and no tolerance options are set" do
    comparison = make_comparison(:a, :b)
    region_scan_calls = 0
    comparison.driver.define_singleton_method(:find_difference_region) do |*args|
      region_scan_calls += 1
      TestDoubles::TestDifference.new(true)
    end

    comparison.quick_equal?

    assert_equal 0, region_scan_calls, "find_difference_region should not run when no tolerance options are configured"
  end

  # Test #different? method
  test "#different? returns false when comparing identical images" do
    comparison = make_comparison(:a, :a)
    refute_predicate comparison, :different?
  end

  test "#different? returns true when comparing different images" do
    comparison = make_comparison(:a, :b)
    assert_predicate comparison, :different?
  end

  # Test #dimensions_changed? method
  test "#dimensions_changed? returns true when images have different dimensions" do
    comparison = make_comparison(:portrait, :a)
    comparison.processed

    assert_predicate comparison, :dimensions_changed?
    assert_kind_of SnapDiff::Reporters::Default, comparison.reporter
  end

  test "#dimensions_changed? returns false when images have same dimensions" do
    comparison = make_comparison(:a, :a)
    comparison.processed

    refute_predicate comparison, :dimensions_changed?
  end

  # Test reporter configuration
  test "#reporter returns Default reporter by default" do
    comparison = make_comparison(:a, :a)
    assert_kind_of SnapDiff::Reporters::Default, comparison.reporter
  end
end
