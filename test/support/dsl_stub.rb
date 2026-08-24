require "active_support/concern"

# Plain top-level module: test scaffolding has no business reopening a gem
# namespace -- least of all the v1 one 3.0 deletes.
module DSLStub
  extend ActiveSupport::Concern

  def setup
    super
    @manager = SnapDiff::SnapManager.new(SnapDiff.config.root / "doc/screenshots")
    SnapDiff.config.screenshoter = ScreenshoterStub
  end

  def teardown
    @manager.cleanup!
    SnapDiff.config.screenshoter = SnapDiff::Screenshoter
    SnapDiff.reset
    super
  end

  # Prepare comparison images and build a Comparison for them
  def make_comparison(fixture_base_image, fixture_new_image = nil, destination: "screenshot", **options)
    fixture_new_image ||= fixture_base_image
    snap = create_snapshot_for(fixture_base_image, fixture_new_image, name: destination)
    SnapDiff::Comparison.new(snap.path, snap.base_path, **options)
  end

  # Prepare images for comparison in a test
  #
  # @param snap [SnapDiff::Snap] the snapshot to prepare
  # @param expected [String] the base name of the original base image
  # @param actual [String] the base name of the original new image
  def set_test_images(snap, expected, actual)
    @manager.provision_snap_with(snap, fixture_image_path_from(actual, snap.format), version: :actual)
    @manager.provision_snap_with(snap, fixture_image_path_from(expected, snap.format), version: :base)
  end

  # `difference` is part of the real Comparison contract (attr_reader), and
  # SnapDiff::Reporting.count reads it to tally the run without triggering
  # a comparison the way `different?` would.
  ImageCompareStub = Struct.new(
    :driver, :driver_options, :shift_distance_limit, :quick_equal?, :different?, :difference, :reporter,
    keyword_init: true
  )

  def build_image_compare_stub(equal: true)
    ImageCompareStub.new(
      driver: ::Minitest::Mock.new,
      reporter: ::Minitest::Mock.new,
      driver_options: SnapDiff.config.default_options,
      shift_distance_limit: nil,
      quick_equal?: equal,
      different?: !equal,
      difference: TestDoubles::TestDifference.new(!equal)
    )
  end

  def take_stable_screenshot_with(snap, stability_time_limit: 0.01, wait: 10)
    screenshoter = SnapDiff::StableScreenshoter.new({stability_time_limit: stability_time_limit, wait: wait})
    screenshoter.take_stable_screenshot(snap)
  end

  def create_snapshot_for(expected, actual = nil, name: nil)
    actual ||= expected
    name ||= "#{actual}_#{Time.now.nsec}"
    @manager.snapshot(name).tap do |snap|
      set_test_images(snap, expected, actual)
    end
  end
end
