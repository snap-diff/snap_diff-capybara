require "active_support/concern"

module CapybaraScreenshotDiff
  module DSLStub
    extend ActiveSupport::Concern

    def setup
      super
      @manager = CapybaraScreenshotDiff::SnapManager.new(Capybara::Screenshot.root / "doc/screenshots")
      Capybara::Screenshot::Diff.screenshoter = Capybara::Screenshot::ScreenshoterStub
    end

    def teardown
      @manager.cleanup!
      Capybara::Screenshot::Diff.screenshoter = Capybara::Screenshot::Screenshoter
      CapybaraScreenshotDiff.reset
      super
    end

    # Prepare comparison images and build ImageCompare for them
    def make_comparison(fixture_base_image, fixture_new_image = nil, destination: "screenshot", **options)
      fixture_new_image ||= fixture_base_image
      snap = create_snapshot_for(fixture_base_image, fixture_new_image, name: destination)
      Capybara::Screenshot::Diff::ImageCompare.new(snap.path, snap.base_path, **options)
    end

    # Prepare images for comparison in a test
    #
    # @param snap [CapybaraScreenshotDiff::Snap] the snapshot to prepare
    # @param expected [String] the base name of the original base image
    # @param actual [String] the base name of the original new image
    def set_test_images(snap, expected, actual)
      @manager.provision_snap_with(snap, fixture_image_path_from(actual, snap.format), version: :actual)
      @manager.provision_snap_with(snap, fixture_image_path_from(expected, snap.format), version: :base)
    end

    ImageCompareStub = Struct.new(
      :driver, :driver_options, :shift_distance_limit, :quick_equal?, :different?, :reporter, keyword_init: true
    )

    def build_image_compare_stub(equal: true)
      ImageCompareStub.new(
        driver: ::Minitest::Mock.new,
        reporter: ::Minitest::Mock.new,
        driver_options: Capybara::Screenshot::Diff.default_options,
        shift_distance_limit: nil,
        quick_equal?: equal,
        different?: !equal
      )
    end

    def take_stable_screenshot_with(snap, stability_time_limit: 0.01, wait: 10)
      screenshoter = Capybara::Screenshot::Diff::StableScreenshoter.new({stability_time_limit: stability_time_limit, wait: wait})
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
end
