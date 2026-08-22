# frozen_string_literal: true

require "active_support/concern"

# Shared contract tests for all image processing drivers.
# Include in any driver test class that uses DSLStub (provides make_comparison).
module DriverContractTests
  extend ActiveSupport::Concern

  included do
    test "[contract] quick_equal? returns true for identical images" do
      comp = make_comparison(:a, :a)
      assert comp.quick_equal?
    end

    test "[contract] different? returns false for identical images" do
      comp = make_comparison(:a, :a)
      assert_not comp.different?
    end

    test "[contract] different? returns true for different images" do
      comp = make_comparison(:a, :c)
      assert comp.different?
    end

    test "[contract] different? generates annotated images for different images" do
      comp = make_comparison(:a, :c)
      assert comp.different?

      assert File.exist?(comp.reporter.annotated_base_image_path)
      assert File.exist?(comp.reporter.annotated_image_path)
    end

    test "[contract] different? does not create annotated images for identical images" do
      comp = make_comparison(:c, :c)
      assert_not comp.different?

      assert_not File.exist?(comp.reporter.annotated_base_image_path)
      assert_not File.exist?(comp.reporter.annotated_image_path)
    end

    # Method presence / signature --------------------------------------------
    # Pins the current de-facto driver interface so a v2 refactor (inheritance
    # -> mixin, class renames) has a regression net. See dissent #4 in the v2
    # architecture design: method NAMES are intentionally out of scope here.

    test "[contract] driver implements the shared driver interface" do
      driver = make_comparison(:a, :a).driver

      %i[
        load_images add_black_box find_difference_region crop from_file
        save_image_to resize_image_to draw_rectangles same_pixels?
        same_dimension? height_for width_for image_area_size dimension supports?
      ].each do |method_name|
        assert_respond_to driver, method_name, "driver should implement ##{method_name}"
      end
    end

    test "[contract] #find_difference_region, #same_pixels?, and #same_dimension? each take a single comparison argument" do
      driver = make_comparison(:a, :a).driver

      assert_equal 1, driver.method(:find_difference_region).arity
      assert_equal 1, driver.method(:same_pixels?).arity
      assert_equal 1, driver.method(:same_dimension?).arity
    end

    test "[contract] #load_images takes exactly the old and new file paths" do
      driver = make_comparison(:a, :a).driver
      assert_equal 2, driver.method(:load_images).arity
    end

    # load_images -------------------------------------------------------------
    # Strengthened (vs. #204's original): a.png/b.png share dimensions, so a
    # swapped return would go undetected. Uses fixtures with DIFFERENT
    # dimensions so slot identity is verifiable by content.

    test "[contract] #load_images returns [old_image, new_image] without swapping slots" do
      driver = make_comparison(:a, :a).driver
      old_path = TEST_IMAGES_DIR / "a.png" # 80x80
      new_path = TEST_IMAGES_DIR / "a_cropped.png" # 80x60

      old_image, new_image = driver.load_images(old_path, new_path)

      assert_equal [80, 80], driver.dimension(old_image)
      assert_equal [80, 60], driver.dimension(new_image)
    end

    # find_difference_region result shape --------------------------------------

    test "[contract] different? exposes a Difference with a region, meta hash, and the comparison" do
      comp = make_comparison(:a, :c)
      assert comp.different?

      difference = comp.difference
      assert_kind_of SnapDiff::ComparisonResult, difference
      assert_not_nil difference.region
      assert_kind_of Hash, difference.meta
      assert_equal comp.driver, difference.comparison.driver
    end

    # Dimension handling --------------------------------------------------------

    test "[contract] #same_dimension? returns true when images share dimensions" do
      driver = make_comparison(:a, :a).driver
      old_image, new_image = driver.load_images(TEST_IMAGES_DIR / "a.png", TEST_IMAGES_DIR / "b.png")
      comparison = SnapDiff::Comparison::Images.new(new_image, old_image, {}, driver)

      assert driver.same_dimension?(comparison)
    end

    test "[contract] #same_dimension? returns false when images differ in dimensions" do
      driver = make_comparison(:a, :a).driver
      old_image, new_image = driver.load_images(TEST_IMAGES_DIR / "a.png", TEST_IMAGES_DIR / "a_cropped.png")
      comparison = SnapDiff::Comparison::Images.new(new_image, old_image, {}, driver)

      assert_not driver.same_dimension?(comparison)
    end

    test "[contract] #width_for, #height_for, #dimension, and #image_area_size agree with each other" do
      driver = make_comparison(:a, :a).driver
      image = driver.from_file(TEST_IMAGES_DIR / "a.png")

      assert_equal [driver.width_for(image), driver.height_for(image)], driver.dimension(image)
      assert_equal driver.width_for(image) * driver.height_for(image), driver.image_area_size(image)
    end

    # Same-image fast paths -------------------------------------------------

    test "[contract] #same_pixels? returns true for pixel-identical images and false otherwise" do
      driver = make_comparison(:a, :a).driver

      old_image, new_image = driver.load_images(TEST_IMAGES_DIR / "a.png", TEST_IMAGES_DIR / "a.png")
      same_comparison = SnapDiff::Comparison::Images.new(new_image, old_image, {}, driver)
      assert driver.same_pixels?(same_comparison)

      other_old_image, other_new_image = driver.load_images(TEST_IMAGES_DIR / "a.png", TEST_IMAGES_DIR / "c.png")
      different_comparison = SnapDiff::Comparison::Images.new(other_new_image, other_old_image, {}, driver)
      assert_not driver.same_pixels?(different_comparison)
    end

    # Option handling -----------------------------------------------------------
    # tolerance/color_distance_limit/skip_area are supported identically by both
    # drivers today; thresholds below are chosen with headroom on both drivers'
    # actual measurements for the a/b and a/d fixture pairs.

    test "[contract] tolerance option treats small differences as equal" do
      comp = make_comparison(:a, :b, tolerance: 0.5)
      assert_not comp.different?
    end

    test "[contract] tolerance option still flags differences exceeding the ratio" do
      comp = make_comparison(:a, :b, tolerance: 0.001)
      assert comp.different?
    end

    test "[contract] color_distance_limit option treats close colors as equal" do
      comp = make_comparison(:a, :b, color_distance_limit: 255)
      assert_not comp.different?
    end

    test "[contract] color_distance_limit option still flags colors beyond the limit" do
      comp = make_comparison(:a, :b, color_distance_limit: 1)
      assert comp.different?
    end

    test "[contract] skip_area option excludes covered regions from comparison" do
      comp = make_comparison(
        :a,
        :d,
        skip_area: [
          Region.from_edge_coordinates(9, 0, 11, 80),
          Region.from_edge_coordinates(79, 79, 80, 80)
        ]
      )
      assert_not comp.different?
    end

    test "[contract] skip_area option still detects differences outside the skipped regions" do
      comp = make_comparison(
        :a,
        :d,
        skip_area: [
          Region.from_edge_coordinates(79, 79, 80, 80),
          Region.from_edge_coordinates(78, 78, 80, 80)
        ]
      )
      assert comp.different?
    end

    # Error behavior on missing files --------------------------------------------

    test "[contract] raises ArgumentError when the base (original) image is missing" do
      error = assert_raises(ArgumentError) do
        SnapDiff::Comparison.new(TEST_IMAGES_DIR / "a.png", TEST_IMAGES_DIR / "does_not_exist.png")
      end
      assert_match(/no original \(base\) screenshot/, error.message)
    end

    test "[contract] raises ArgumentError when the new image is missing" do
      error = assert_raises(ArgumentError) do
        SnapDiff::Comparison.new(TEST_IMAGES_DIR / "does_not_exist.png", TEST_IMAGES_DIR / "a.png")
      end
      assert_match(/no new screenshot/, error.message)
    end

    # Resize behavior -------------------------------------------------------
    # Behavioral (vs. #204's method-presence check above): asserts the actual
    # output dimensions, not just that #resize_image_to responds.

    test "[contract] resize_image_to resizes a non-square source to the exact requested non-square dimensions" do
      driver = make_comparison(:a, :a).driver
      source = driver.from_file(TEST_IMAGES_DIR / "portrait.png") # 3x6, non-square

      resized = driver.resize_image_to(source, 40, 30)

      assert_equal [40, 30], driver.dimension(resized)
    end
  end
end
