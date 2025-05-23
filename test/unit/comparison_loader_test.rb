# frozen_string_literal: true

require "test_helper"
require "support/test_doubles"
require "capybara/screenshot/diff/comparison_loader"

module Capybara
  module Screenshot
    module Diff
      class ComparisonLoaderTest < ActiveSupport::TestCase
        include TestDoubles

        def setup
          @base_path = Pathname.new("base/path.png")
          @new_path = Pathname.new("new/path.png")
          @options = {tolerance: 0.01}
          @driver = TestDriver.new
          @loader = ComparisonLoader.new(@driver)
        end

        test "#call returns Comparison instance with correct attributes" do
          comparison = @loader.call(@base_path, @new_path, @options)

          assert_kind_of Comparison, comparison
          assert_equal :base_image, comparison.base_image
          assert_equal :new_image, comparison.new_image
          assert_equal @options, comparison.options
          assert_equal @driver, comparison.driver
        end

        test "#call loads base and new images in correct order" do
          # Configure the driver to return specific images
          images = [:first_image, :second_image]
          driver = TestDriver.new(false, images)
          loader = ComparisonLoader.new(driver)

          comparison = loader.call(@base_path, @new_path, {})

          assert_equal :first_image, comparison.base_image
          assert_equal :second_image, comparison.new_image
        end

        test "#call passes options to the comparison" do
          custom_options = {tolerance: 0.05, median_filter_window_size: 3}
          comparison = @loader.call(@base_path, @new_path, custom_options)

          assert_equal custom_options, comparison.options
        end

        test "#call uses driver to load images with correct paths" do
          loader = ComparisonLoader.new(@driver)
          loader.call(@base_path, @new_path, {})

          assert @driver.load_images_called
          assert_equal [@base_path, @new_path], @driver.load_images_args
        end
      end
    end
  end
end
