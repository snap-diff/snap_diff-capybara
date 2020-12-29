# frozen_string_literal: true

require "test_helper"
require "minitest/stub_const"

module Capybara
  module Screenshot
    module Diff
      class ImageCompareTest < ActionDispatch::IntegrationTest
        include TestHelper

        test "it can be instantiated with chunky_png driver" do
          comparison = ImageCompare.new("images/b.png")
          assert_kind_of Drivers::ChunkyPNGDriver, comparison.driver
        end

        test "it can be instantiated with explicit chunky_png adapter" do
          comparison = ImageCompare.new("images/b.png", driver: :chunky_png)
          assert_kind_of Drivers::ChunkyPNGDriver, comparison.driver
        end

        test "it can be instantiated with vips adapter" do
          skip unless defined?(Capybara::Screenshot::Diff::Drivers::VipsDriverTest)
          comparison = ImageCompare.new("images/b.png", driver: :vips)
          assert_kind_of Drivers::VipsDriver, comparison.driver
        end

        test "it can be instantiated with vips adapter and tolerance option" do
          skip unless defined?(Capybara::Screenshot::Diff::Drivers::VipsDriverTest)
          comp = make_comparison(:a, :b, driver: :vips, tolerance: 0.02)
          assert comp.quick_equal?
          assert_not comp.different?
        end

        test "could pass use tolerance for chunky_png driver" do
          ImageCompare.new("images/b.png", driver: :chunky_png, tolerance: 0.02)
        end

        test "it can be instantiated with dimensions" do
          assert ImageCompare.new("images/b.png", dimensions: [80, 80])
        end

        test "for driver: :auto returns first from available drivers" do
          skip unless defined?(Capybara::Screenshot::Diff::Drivers::VipsDriverTest)
          comparison = ImageCompare.new("images/b.png", driver: :auto)
          assert_kind_of Drivers::VipsDriver, comparison.driver
        end

        test "for driver: :auto raise error if no drivers are available" do
          Capybara::Screenshot::Diff.stub_const(:AVAILABLE_DRIVERS, []) do
            assert_raise(RuntimeError) do
              ImageCompare.new("images/b.png", driver: :auto)
            end
          end
        end
      end
    end
  end
end
