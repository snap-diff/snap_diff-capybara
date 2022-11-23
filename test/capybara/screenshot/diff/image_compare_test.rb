# frozen_string_literal: true

require "test_helper"
require "minitest/stub_const"
require "capybara/screenshot/diff/drivers/chunky_png_driver"
require "capybara/screenshot/diff/drivers/vips_driver"

module Capybara
  module Screenshot
    module Diff
      class ImageCompareTest < ActionDispatch::IntegrationTest
        include TestHelper

        test "it can be instantiated with chunky_png driver" do
          comparison = ImageCompare.new("images/b.png", nil)
          assert_kind_of Drivers::ChunkyPNGDriver, comparison.driver
        end

        test "it can be instantiated with explicit chunky_png adapter" do
          comparison = ImageCompare.new("images/b.png", nil, driver: :chunky_png)
          assert_kind_of Drivers::ChunkyPNGDriver, comparison.driver
        end

        test "it can be instantiated with vips adapter" do
          comparison = ImageCompare.new("images/b.png", nil, driver: :vips)
          assert_kind_of Drivers::VipsDriver, comparison.driver
        end

        test "it can be instantiated with vips adapter and tolerance option" do
          comp = make_comparison(:a, :b, driver: :vips, tolerance: 0.02)
          assert comp.quick_equal?
          assert_not comp.different?
        end

        test "could pass use tolerance for chunky_png driver" do
          ImageCompare.new("images/b.png", nil, driver: :chunky_png, tolerance: 0.02)
        end

        test "it can be instantiated with dimensions" do
          assert ImageCompare.new("images/b.png", nil, dimensions: [80, 80])
        end

        test "for driver: :auto returns first from available drivers" do
          comparison = ImageCompare.new("images/b.png", nil, driver: :auto)
          assert_kind_of Drivers::VipsDriver, comparison.driver
        end

        test "for driver: :auto raise error if no drivers are available" do
          Capybara::Screenshot::Diff.stub_const(:AVAILABLE_DRIVERS, []) do
            assert_raise(RuntimeError) do
              ImageCompare.new("images/b.png", nil, driver: :auto)
            end
          end
        end
      end

      class IntegrationRegressionTest < ActionDispatch::IntegrationTest
        include TestHelper

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
            Dir.chdir File.expand_path("../../../images", __dir__) do
              images.each do |image|
                other_images = images - [image]
                other_images.each do |different_image|
                  comparison = make_comparison(image, different_image, **driver)
                  assert_not(
                    comparison.quick_equal?,
                    "compare #{image} with #{different_image} with #{driver} driver should not be quick_equal"
                  )
                  assert(
                    comparison.different?,
                    "compare #{image} with #{different_image} with #{driver} driver should be different"
                  )
                end
              end
            end
          end
        end

        def all_fixtures_images_names
          fixtures_images = Dir[File.expand_path("../../../images/*.png", __dir__)]
          fixtures_images.map { |f| File.basename(f).chomp(".png") }
        end
      end
    end
  end
end
