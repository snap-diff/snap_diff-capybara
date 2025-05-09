# frozen_string_literal: true

require "test_helper"
require "minitest/stub_const"
require "capybara/screenshot/diff/drivers/chunky_png_driver"
if defined?(Vips)
  require "capybara/screenshot/diff/drivers/vips_driver"
elsif ENV["SCREENSHOT_DRIVER"] == "vips"
  raise 'Required `ruby-vips` gem or `vips` library is missing. Ensure "ruby-vips" gem and "vips" library is installed.'
end

module Capybara
  module Screenshot
    module Diff
      class ImageCompareTest < ActionDispatch::IntegrationTest
        include CapybaraScreenshotDiff::DSLStub

        test "it can be instantiated with chunky_png driver" do
          comparison = make_comparison(:b)
          assert_kind_of Drivers::ChunkyPNGDriver, comparison.driver
        end

        test "it can be instantiated with explicit chunky_png adapter" do
          comparison = make_comparison(:b, driver: :chunky_png)
          assert_kind_of Drivers::ChunkyPNGDriver, comparison.driver
        end

        test "it can be instantiated with vips adapter" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
          comparison = make_comparison(:b, driver: :vips)
          assert_kind_of Drivers::VipsDriver, comparison.driver
        end

        test "for vips it generates annotation files on difference" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
          comparison = make_comparison(:a, :b, driver: :vips)

          assert comparison.different?

          assert_same_images("a-and-b.diff.png", comparison.reporter.annotated_base_image_path)
          assert_same_images("b-and-a.diff.png", comparison.reporter.annotated_image_path)
        end

        test "it can handle very long input filenames" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
          filename = %w[this-0000000000000000000000000000000000000000000000000-path/is/extremely/
            long/and/if/the/directories/are/flattened/in/
            the_temporary_they_will_cause_the_filename_to_exceed_
            the_limit_on_most_unix_systems_which_nobody_wants.png].join
          comparison = make_comparison(:a, :b, destination: (Rails.root / filename), driver: :vips)

          assert comparison.different?
        end

        test "it can be instantiated with vips adapter and tolerance option" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
          comp = make_comparison(:a, :b, driver: :vips, tolerance: 0.02)
          assert comp.quick_equal?
          assert_not comp.different?
        end

        test "could pass use tolerance for chunky_png driver" do
          comp = make_comparison(:a, :b, driver: :chunky_png, tolerance: 0.02)
          assert comp.quick_equal?
          assert_not comp.different?
        end

        test "it can be instantiated with dimensions" do
          comp = make_comparison(:b, dimensions: [80, 80])
          assert comp.quick_equal?
          assert_not comp.different?
        end

        test "for driver: :auto returns first from available drivers" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
          comparison = make_comparison(:b, driver: :auto)
          assert_kind_of Drivers::VipsDriver, comparison.driver
        end

        test "for driver: :auto raise error if no drivers are available" do
          Capybara::Screenshot::Diff.stub_const(:AVAILABLE_DRIVERS, []) do
            assert_raise(RuntimeError) do
              comparison = make_comparison(:b, driver: :auto)
              assert comparison.quick_equal?
            end
          end
        end
      end

      class IntegrationRegressionTest < ActionDispatch::IntegrationTest
        include CapybaraScreenshotDiff::DSLStub

        AVAILABLE_DRIVERS = [{}, {driver: :chunky_png}]

        test "the same images should be quick equal and not different" do
          images = all_fixtures_images_names
          AVAILABLE_DRIVERS.each do |driver|
            Dir.chdir File.expand_path("../../../images", __dir__) do
              images.each do |old_img|
                new_img = old_img
                comparison = make_comparison(old_img, new_img, **driver)
                assert(
                  comparison.quick_equal?,
                  "compare #{old_img} with #{new_img} with #{driver} driver should be quick_equal"
                )
                assert_not(
                  comparison.different?,
                  "compare #{old_img} with #{new_img} with #{driver} driver should not be different"
                )
              end
            end
          end
        end

        test "the different images should not be quick equal and different" do
          images = all_fixtures_images_names

          AVAILABLE_DRIVERS.each do |driver|
            images.each do |image|
              other_images = images - [image]
              other_images.each do |different_image|
                comparison = make_comparison(image, different_image, **driver)
                assert_not(
                  comparison.quick_equal?,
                  "compare #{image.inspect} with #{different_image.inspect} using #{driver} driver should not be quick_equal"
                )
                assert(
                  comparison.different?,
                  "compare #{image.inspect} with #{different_image.inspect} using #{driver} driver should be different"
                )
              end
            end
          end
        end

        def all_fixtures_images_names
          %w[a a_cropped b c d portrait portrait_b]
        end
      end
    end
  end
end
