# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/reporters/default"

unless defined?(Vips)
  warn "VIPS not present. Skipping VIPS driver tests."
  return
end
require "capybara/screenshot/diff/drivers/vips_driver"

module Capybara::Screenshot::Diff
  class Reporters::DefaultTest < ActiveSupport::TestCase
    setup do
      @_tmpdir = Pathname.new(Dir.mktmpdir)
    end

    teardown do
      FileUtils.remove_entry @_tmpdir if @_tmpdir
    end

    test "for vips driver generates heatmap diff file" do
      skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
      driver = Drivers::VipsDriver.new
      comparison = build_comparison_for(driver, "a.png", "b.png")
      reporter = Reporters::Default.new(driver.find_difference_region(comparison))

      reporter.generate

      assert_same_images "a-and-b.heatmap.diff.png", reporter.heatmap_diff_path
    end

    private

    def build_comparison_for(driver, *images)
      new_image = driver.from_file(TEST_IMAGES_DIR.join(images.first))
      base_image = driver.from_file(TEST_IMAGES_DIR.join(images.last))

      Comparison.new(new_image, base_image, {}, driver, @_tmpdir / images.first, @_tmpdir / images.last)
    end
  end
end
