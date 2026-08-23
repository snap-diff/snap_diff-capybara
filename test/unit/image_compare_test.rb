# frozen_string_literal: true

require "test_helper"

# No `if defined?(Vips)` guard and no driver-selection tests: 2.1 removed the
# driver abstraction, so `ruby-vips` is a gemspec runtime dependency and
# SnapDiff::Drivers::VipsDriver is the only backend there is.
class ImageCompareTest < ActiveSupport::TestCase
  include DSLStub

  test "#initialize always builds the vips driver" do
    assert_kind_of SnapDiff::Drivers::VipsDriver, make_comparison(:b).driver
  end

  test "#different? generates annotated diff images" do
    comparison = make_comparison(:a, :b)

    assert comparison.different?

    assert_same_images("a-and-b.diff.png", comparison.reporter.annotated_base_image_path)
    assert_same_images("b-and-a.diff.png", comparison.reporter.annotated_image_path)
  end

  test "#different? handles very long input filenames" do
    filename = %w[this-0000000000000000000000000000000000000000000000000-path/is/extremely/
      long/and/if/the/directories/are/flattened/in/
      the_temporary_they_will_cause_the_filename_to_exceed_
      the_limit_on_most_unix_systems_which_nobody_wants.png].join
    comparison = make_comparison(:a, :b, destination: (Rails.root / filename))

    assert comparison.different?
  end

  test "#initialize respects the tolerance option" do
    comp = make_comparison(:a, :b, tolerance: 0.02)
    assert comp.quick_equal?
    assert_not comp.different?
    assert_equal 0.02, comp.driver_options[:tolerance]
  end

  test "#initialize with dimensions creates valid comparison" do
    comp = make_comparison(:b, dimensions: [80, 80])
    assert comp.quick_equal?
    assert_not comp.different?
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
# fixtures are known to differ only within [11,3,48,20].
class SkipAreaMasksVcsBaselineTest < ActiveSupport::TestCase
  include DSLStub

  test "#different? masks the VCS-checked-out baseline, not just the new screenshot" do
    full_image_region = Region.from_edge_coordinates(0, 0, 80, 80)
    comparison = make_comparison(:a, :c, destination: "skip_area_vcs_baseline", skip_area: [full_image_region])

    refute_predicate comparison, :different?
  end
end

class IntegrationRegressionTest < ActiveSupport::TestCase
  include DSLStub

  # Was a two-element driver matrix ({} and {driver: :chunky_png}); with one
  # backend the outer loop had one iteration, so it is gone rather than left
  # as a loop over a single element.
  test "identical images are quick_equal and not different" do
    images = all_fixtures_images_names
    Dir.chdir File.expand_path("../fixtures/images", __dir__) do
      images.each do |old_img|
        new_img = old_img
        comparison = make_comparison(old_img, new_img)
        assert(comparison.quick_equal?, "compare #{old_img} with #{new_img} should be quick_equal")
        assert_not(comparison.different?, "compare #{old_img} with #{new_img} should not be different")
      end
    end
  end

  test "different images are not quick_equal and are marked as different" do
    images = all_fixtures_images_names

    images.each do |image|
      other_images = images - [image]
      other_images.each do |different_image|
        comparison = make_comparison(image, different_image)
        assert_not(
          comparison.quick_equal?,
          "compare #{image.inspect} with #{different_image.inspect} should not be quick_equal"
        )
        assert(
          comparison.different?,
          "compare #{image.inspect} with #{different_image.inspect} should be different"
        )
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
