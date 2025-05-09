# frozen_string_literal: true

require "test_helper"
require_relative "test_doubles"

module Capybara
  module Screenshot
    module Diff
      class ComparisonLoaderTest < ActionDispatch::IntegrationTest
        include CapybaraScreenshotDiff::DSLStub
        include TestDoubles

        test "loads images and applies preprocessing" do
          # Setup
          base_path = Pathname.new("base/path.png")
          new_path = Pathname.new("new/path.png")
          options = {tolerance: 0.01}

          raw_images = [:raw_base_image, :raw_new_image]

          driver = TestDriver.new(false, raw_images)

          # Action
          loader = ComparisonLoader.new(driver)
          comparison = loader.call(base_path, new_path, options)

          # Verify the comparison object
          assert_kind_of Comparison, comparison
          assert_equal raw_images[1], comparison.new_image
          assert_equal raw_images[0], comparison.base_image
          assert_equal options, comparison.options
          assert_equal driver, comparison.driver
        end
      end
    end
  end
end
