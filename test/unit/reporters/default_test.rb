# frozen_string_literal: true

require "test_helper"
require "snap_diff/reporters/default"

require "snap_diff/drivers/vips_driver" if defined?(Vips)

class DefaultReporterTest < ActiveSupport::TestCase
  setup do
    skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
    @_tmpdir = Pathname.new(Dir.mktmpdir)
  end

  teardown do
    FileUtils.remove_entry @_tmpdir if @_tmpdir
  end

  test "for vips driver generates heatmap diff file" do
    driver = SnapDiff::Drivers::VipsDriver.new
    comparison = build_comparison_for(driver, "a.png", "b.png")
    reporter = SnapDiff::Reporters::Default.new(driver.find_difference_region(comparison))

    reporter.generate

    assert_same_images "a-and-b.heatmap.diff.png", reporter.heatmap_diff_path
  end

  test "#clean_tmp_files removes heatmap diff along with other diff artifacts" do
    driver = SnapDiff::Drivers::VipsDriver.new
    comparison = build_comparison_for(driver, "a.png", "b.png")
    reporter = SnapDiff::Reporters::Default.new(driver.find_difference_region(comparison))
    reporter.generate

    assert_predicate reporter.heatmap_diff_path, :exist?

    reporter.clean_tmp_files

    assert_not reporter.annotated_image_path.exist?, "diff should be cleaned"
    assert_not reporter.annotated_base_image_path.exist?, "base diff should be cleaned"
    assert_not reporter.heatmap_diff_path.exist?, "heatmap diff should be cleaned"
  end

  # The test above calls clean_tmp_files directly, so #generate's OWN call to
  # it on the equal path had no coverage: deleting that line left the suite
  # green while every passing comparison leaked the previous run's diff
  # artifacts, which the next run then reports as stale output.
  test "#generate removes the previous run's diff artifacts when the images are equal" do
    driver = SnapDiff::Drivers::VipsDriver.new
    reporter = SnapDiff::Reporters::Default.new(driver.find_difference_region(build_comparison_for(driver, "a.png", "b.png")))
    reporter.generate # a.png vs b.png differ: writes the artifacts

    assert_predicate reporter.annotated_image_path, :exist?
    assert_predicate reporter.heatmap_diff_path, :exist?

    # Equal images, but the SAME artifact paths as the comparison above, so
    # what gets cleaned is exactly what got written.
    equal_image = driver.from_file(TEST_IMAGES_DIR.join("a.png"))
    equal_difference = driver.find_difference_region(
      SnapDiff::Comparison::Images.new(equal_image, equal_image, {}, driver, @_tmpdir / "a.png", @_tmpdir / "b.png")
    )
    assert_predicate equal_difference, :equal?

    assert_nil SnapDiff::Reporters::Default.new(equal_difference).generate

    assert_not reporter.annotated_image_path.exist?, "diff should be cleaned on the equal path"
    assert_not reporter.annotated_base_image_path.exist?, "base diff should be cleaned on the equal path"
    assert_not reporter.heatmap_diff_path.exist?, "heatmap diff should be cleaned on the equal path"
  end

  test "failure message reports metrics without leaking image objects" do
    driver = SnapDiff::Drivers::VipsDriver.new
    comparison = build_comparison_for(driver, "a.png", "b.png")
    difference = driver.find_difference_region(comparison)
    difference.meta[:difference_level] = 0.42

    message = SnapDiff::Reporters::Default.new(difference).generate

    assert_includes message, "changed region"
    assert_includes message, "difference level"
    assert_not_includes message, "Vips::Image"
    # The signature of a leaked Ruby object in a message: `#<Vips::Image 0x...>`.
    assert_not_includes message, "#<"
  end

  # Every number in the message needs a denominator or a stated unit: an
  # `area_size` on its own and a bare four-number `region` were the two
  # things readers could not interpret.
  test "failure message gives the changed area a denominator and the region its interpretation" do
    driver = SnapDiff::Drivers::VipsDriver.new
    difference = driver.find_difference_region(build_comparison_for(driver, "a.png", "b.png", tolerance: 0.001))

    message = SnapDiff::Reporters::Default.new(difference).generate

    assert_includes message, "100 of 6400 px (1.56% of the 80x80 image)"
    assert_includes message, "changed region: [20.0,15.0,30.0,25.0] (left,top,right,bottom edges)"
    assert_includes message, "difference level: 0.00765625 (0.77% of the image area)"
  end

  # VCR's error restates the config it applied; half of "why did this fail?"
  # is answered by the threshold the comparison was judged against.
  test "failure message states the thresholds that were applied" do
    driver = SnapDiff::Drivers::VipsDriver.new
    difference = driver.find_difference_region(
      build_comparison_for(driver, "a.png", "b.png", tolerance: 0.001, color_distance_limit: 20)
    )

    message = SnapDiff::Reporters::Default.new(difference).generate

    assert_includes message, "judged against: tolerance 0.001, color_distance_limit 20"
  end

  test "failure message says so when no threshold was configured" do
    driver = SnapDiff::Drivers::VipsDriver.new
    difference = driver.find_difference_region(build_comparison_for(driver, "a.png", "b.png"))

    message = SnapDiff::Reporters::Default.new(difference).generate

    assert_includes message, "judged against: no tolerance thresholds configured (any difference fails)"
  end

  test "failure message labels every artifact it lists" do
    driver = SnapDiff::Drivers::VipsDriver.new
    comparison = build_comparison_for(driver, "a.png", "b.png")
    FileUtils.cp(TEST_IMAGES_DIR.join("a.png"), comparison.new_image_path)
    FileUtils.cp(TEST_IMAGES_DIR.join("b.png"), comparison.base_image_path)
    reporter = SnapDiff::Reporters::Default.new(driver.find_difference_region(comparison))

    message = reporter.generate.squeeze(" ")

    assert_includes message, "baseline: #{comparison.base_image_path}"
    assert_includes message, "actual: #{comparison.new_image_path}"
    assert_includes message, "baseline annotated: #{reporter.annotated_base_image_path}"
    assert_includes message, "actual annotated: #{reporter.annotated_image_path}"
    assert_includes message, "heatmap: #{reporter.heatmap_diff_path}"
  end

  # Issue #260: the message must never name a file that is not on disk.
  test "failure message omits artifacts that were never written" do
    driver = SnapDiff::Drivers::VipsDriver.new
    comparison = build_comparison_for(driver, "a.png", "b.png")
    reporter = SnapDiff::Reporters::Default.new(driver.find_difference_region(comparison))

    message = reporter.generate.squeeze(" ")

    assert_not_includes message, "baseline: "
    assert_not_includes message, "actual: "
    assert_includes message, "heatmap: #{reporter.heatmap_diff_path}"
  end

  test "artifact paths are printed relative to the configured root, absolute when outside it" do
    driver = SnapDiff::Drivers::VipsDriver.new
    comparison = build_comparison_for(driver, "a.png", "b.png")
    reporter = SnapDiff::Reporters::Default.new(driver.find_difference_region(comparison))

    with_config_root(@_tmpdir) do
      assert_includes reporter.generate.squeeze(" "), "heatmap: a.heatmap.diff.png"
    end

    with_config_root(@_tmpdir / "elsewhere") do
      assert_includes reporter.generate.squeeze(" "), "heatmap: #{reporter.heatmap_diff_path}"
    end
  end

  private

  def with_config_root(root)
    previous = SnapDiff.config.root
    SnapDiff.config.root = root
    yield
  ensure
    SnapDiff.config.root = previous
  end

  def build_comparison_for(driver, *images, **options)
    new_image = driver.from_file(TEST_IMAGES_DIR.join(images.first))
    base_image = driver.from_file(TEST_IMAGES_DIR.join(images.last))

    SnapDiff::Comparison::Images.new(new_image, base_image, options, driver, @_tmpdir / images.first, @_tmpdir / images.last)
  end
end
