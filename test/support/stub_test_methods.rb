# frozen_string_literal: true

require_relative "screenshoter_stub"

module Capybara
  module Screenshot
    module Diff
      module TestMethodsStub
        extend ActiveSupport::Concern

        included do
          setup do
            Diff.screenshoter = ScreenshoterStub
          end

          teardown do
            Diff.screenshoter = Screenshoter
          end
        end

        # Prepare comparison images and build ImageCompare for them
        def make_comparison(fixture_base_image, fixture_new_image, destination: nil, **options)
          destination ||= Rails.root / "doc/screenshots/screenshot.png"

          set_test_images(destination, fixture_base_image, fixture_new_image)

          ImageCompare.build(destination, ScreenshotMatcher.base_image_path_from(destination), **options)
        end

        def set_test_images(destination, original_base_image, original_new_image)
          FileUtils.mkdir_p destination.dirname
          FileUtils.cp TEST_IMAGES_DIR / "#{original_new_image}.png", destination
          FileUtils.cp TEST_IMAGES_DIR / "#{original_base_image}.png", ScreenshotMatcher.base_image_path_from(destination)
        end
      end
    end
  end
end
