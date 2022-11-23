# frozen_string_literal: true

require "test_helper"

module Capybara
  module Screenshot
    module Diff
      class StabilizationTest < ActionDispatch::IntegrationTest
        include TestMethods
        include TestHelper

        ImageCompareStub = Struct.new(
          :old_file_name, :new_file_name, :driver, :reset, :driver_options, :shift_distance_limit
        )

        test "several iterations to take stable screenshot" do
          image_compare_stub = ImageCompareStub.new(
            "old.png", "tmp/01_a.png", ::Minitest::Mock.new, nil, Capybara::Screenshot::Diff.default_options, nil
          )

          mock = ::Minitest::Mock.new(image_compare_stub)

          mock.expect(:quick_equal?, false)
          mock.expect(:quick_equal?, false)
          mock.expect(:quick_equal?, true)

          take_stable_screenshot(mock, stability_time_limit: 1, wait: 1, crop: nil)
        end
      end
    end
  end
end
