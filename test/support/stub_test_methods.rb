# frozen_string_literal: true

require_relative "screenshoter_stub"

module Capybara
  module Screenshot
    module Diff
      module TestMethodsStub
        extend ActiveSupport::Concern

        included do
          setup do
            @manager = CapybaraScreenshotDiff::SnapManager.new(Rails.root / "doc/screenshots")
            Diff.screenshoter = ScreenshoterStub
          end

          teardown do
            @manager.clean!
            Diff.screenshoter = Screenshoter
          end
        end

        # Prepare comparison images and build ImageCompare for them
        def make_comparison(fixture_base_image, fixture_new_image, destination: "screenshot", **options)
          snap = @manager.snap_for(destination)

          set_test_images(snap, fixture_base_image, fixture_new_image)

          ImageCompare.new(snap.path, snap.base_path, **options)
        end

        def set_test_images(snap, original_base_image, original_new_image, ext: "png")
          @manager.provision_snap_with(snap, fixture_image_path_from(original_new_image, snap.format), version: :actual)
          @manager.provision_snap_with(snap, fixture_image_path_from(original_base_image, snap.format), version: :base)
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
          screenshoter = StableScreenshoter.new({stability_time_limit: stability_time_limit, wait: wait})
          screenshoter.take_stable_screenshot(snap)
        end
      end
    end
  end
end
