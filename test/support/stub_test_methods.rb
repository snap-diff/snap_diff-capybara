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
          destination = snap.path
          snap.manager.create_output_directory_for(destination)

          ext = destination.extname[1..] if destination.extname.present?
          FileUtils.cp(TEST_IMAGES_DIR / "#{original_new_image}.#{ext}", snap.path)
          FileUtils.cp(TEST_IMAGES_DIR / "#{original_base_image}.#{ext}", snap.base_path)
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

        def take_stable_screenshot_with(screenshot_path, stability_time_limit: 0.01, wait: 10)
          screenshoter = StableScreenshoter.new({stability_time_limit: stability_time_limit, wait: wait})
          screenshoter.take_stable_screenshot(screenshot_path)
        end
      end
    end
  end
end
