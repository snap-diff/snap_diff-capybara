# frozen_string_literal: true

require "test_helper"

module Capybara
  module Screenshot
    module Diff
      class CompareApiTest < ActiveSupport::TestCase
        test ".compare returns ImageCompare instance" do
          result = Diff.compare(
            TEST_IMAGES_DIR / "a.png",
            TEST_IMAGES_DIR / "a.png"
          )
          assert_kind_of ImageCompare, result
        end

        test ".compare detects identical images" do
          result = Diff.compare(
            TEST_IMAGES_DIR / "a.png",
            TEST_IMAGES_DIR / "a.png"
          )
          assert result.quick_equal?
          assert_not result.different?
        end

        test ".compare detects different images" do
          result = Diff.compare(
            TEST_IMAGES_DIR / "a.png",
            TEST_IMAGES_DIR / "b.png"
          )
          assert_not result.quick_equal?
          assert result.different?
        end

        test ".compare accepts driver option" do
          skip "VIPS not present" unless defined?(Vips)

          result = Diff.compare(
            TEST_IMAGES_DIR / "a.png",
            TEST_IMAGES_DIR / "a.png",
            driver: :vips
          )
          assert result.quick_equal?
        end

        test ".compare accepts tolerance options" do
          skip "VIPS not present" unless defined?(Vips)

          result = Diff.compare(
            TEST_IMAGES_DIR / "a.png",
            TEST_IMAGES_DIR / "b.png",
            driver: :vips,
            tolerance: 1.0
          )
          assert_not result.different?
        end
      end
    end
  end
end
