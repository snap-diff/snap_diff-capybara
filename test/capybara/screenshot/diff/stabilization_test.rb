# frozen_string_literal: true

require "test_helper"

module Capybara
  module Screenshot
    module Diff
      class StabilizationTest < ActionDispatch::IntegrationTest
        include TestMethods
        include TestHelper

        test 'several iterations to take stable screenshot' do
          # @type [ImageCompare]
          comparison = ::Minitest::Mock.new
          def comparison.old_file_name; 'old.png'; end
          def comparison.new_file_name; '01_a.png'; end
          def comparison.driver; :vips; end
          def comparison.reset; end
          def comparison.driver_options; Capybara::Screenshot::Diff.default_options; end
          def comparison.shift_distance_limit; nil; end

          comparison.expect(:quick_equal?, false)
          comparison.expect(:quick_equal?, false)
          comparison.expect(:quick_equal?, true)

          take_stable_screenshot(comparison, stability_time_limit: 1, wait: 1, crop: nil)
        end
      end
    end
  end
end
