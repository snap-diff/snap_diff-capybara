# frozen_string_literal: true

require "benchmark"

require "capybara/screenshot/diff"
require "capybara/screenshot/diff/drivers/vips_driver"
require "capybara/screenshot/diff/drivers/chunky_png_driver"

module Capybara::Screenshot::Diff
  class Drivers::FindRegionBenchmark
    TEST_IMAGES_DIR = Pathname.new(File.expand_path("../../test/fixtures/images", __dir__))
    APP_SCREENSHOTS_DIR = Pathname.new(
      File.expand_path("../../test/fixtures/app/doc/screenshots/chrome/macos/", __dir__)
    )

    def for_medium_size_screens
      image_path = (APP_SCREENSHOTS_DIR / "index.png").to_path
      base_image_path = (APP_SCREENSHOTS_DIR / "index-blur_active_element-enabled.png").to_path

      Benchmark.bm(50) do |x|
        experiment_for(x, :chunky_png, :different?, "same images", image_path, image_path)
        experiment_for(x, :vips, :different?, "same images", image_path, image_path)
        experiment_for(x, :chunky_png, :quick_equal?, "different images", image_path, base_image_path)
        experiment_for(x, :vips, :quick_equal?, "different images", image_path, base_image_path)
      end
    end

    def for_small_images
      image_path = (TEST_IMAGES_DIR / "a.png").to_path
      base_image_path = (TEST_IMAGES_DIR / "b.png").to_path

      Benchmark.bm(50) do |x|
        experiment_for(x, :chunky_png, :different?, "same images", image_path, image_path)
        experiment_for(x, :vips, :different?, "same images", image_path, image_path)
        experiment_for(x, :chunky_png, :quick_equal?, "different images", image_path, base_image_path)
        experiment_for(x, :vips, :quick_equal?, "different images", image_path, base_image_path)
      end
    end

    private

    def experiment_for(x, driver, method, suffix, new_path, base_path)
      x.report("[#{suffix}] #{driver}##{method}") do
        50.times do
          ImageCompare.new(new_path, base_path, driver: driver).public_send(method)

          Vips.cache_set_max(0)
          Vips.cache_set_max(1000)
        end
      end
    end
  end
end
