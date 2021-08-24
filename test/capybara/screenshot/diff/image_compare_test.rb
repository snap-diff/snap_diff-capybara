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
        IMAGES = Dir[File.expand_path("../../../images/*.png", __dir__)].map { |f| File.basename(f).chomp('.png') }

        { default: Drivers::ChunkyPNGDriver, chunky_png: Drivers::ChunkyPNGDriver,
            # vips: Drivers::VipsDriver, auto: Drivers::VipsDriver
        }.each do |driver, driver_class|
          unless driver_class == Drivers::VipsDriver && !defined?(Capybara::Screenshot::Diff::Drivers::VipsDriverTest)
          driver_opts = driver == :default ? {} : { driver: driver }
          Dir.chdir File.expand_path("../../../images", __dir__) do
            IMAGES.each do |old_img|
              IMAGES.each do |new_img|
                test "compare #{old_img} with #{new_img} with #{driver} driver" do
                  comparison = make_comparison(old_img, new_img, **driver_opts)
                  assert_kind_of driver_class, comparison.driver
                  same = old_img == new_img
                  assert_equal same, comparison.quick_equal?
                  assert_equal !same, comparison.different?
                end
              end
            end
          end
          end
        end

        # test "it can be instantiated with vips adapter and tolerance option" do
        #   skip unless defined?(Capybara::Screenshot::Diff::Drivers::VipsDriverTest)
        #   comp = make_comparison(:a, :b, driver: :vips, tolerance: 0.02)
        #   assert comp.quick_equal?
        #   assert_not comp.different?
        # end
        #
        # test "could pass use tolerance for chunky_png driver" do
        #   ImageCompare.new("images/b.png", driver: :chunky_png, tolerance: 0.02)
        # end
        #
        # test "it can be instantiated with dimensions" do
        #   assert ImageCompare.new("images/b.png", dimensions: [80, 80])
        # end
        #
        # test "for driver: :auto raise error if no drivers are available" do
        #   Capybara::Screenshot::Diff.stub_const(:AVAILABLE_DRIVERS, []) do
        #     assert_raise(RuntimeError) do
        #       ImageCompare.new("images/b.png", driver: :auto)
        #     end
        #   end
        # end
      end
    end
  end
end
