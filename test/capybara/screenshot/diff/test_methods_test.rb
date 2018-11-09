require 'test_helper'

module Capybara
  module Screenshot
    module Diff
      class TestMethodsTest < ActionDispatch::IntegrationTest
        include TestMethods
        include TestHelper

        def test_assert_image_not_changed
          message = assert_image_not_changed('caller', 'name', make_comparison(:a, :c))
          value = RUBY_VERSION >= '2.4' ? 187.4 : 188
          assert_equal <<-MSG.strip_heredoc.chomp, message
            Screenshot does not match for 'name' (area: 684px [11, 3, 48, 20], max_color_distance: #{value})
            #{Rails.root}/screenshot.png
            #{Rails.root}/screenshot_0.png~
            #{Rails.root}/screenshot_1.png~
            at caller
          MSG
        end

        def test_assert_image_not_changed_with_shift_distance_limit
          message =
            assert_image_not_changed('caller', 'name', make_comparison(:a, :c, shift_distance_limit: 1))
          value = RUBY_VERSION >= '2.4' ? 5.0 : 5
          assert_equal <<-MSG.strip_heredoc.chomp, message
            Screenshot does not match for 'name' (area: 684px [11, 3, 48, 20], max_color_distance: #{value}, max_shift_distance: 15)
            #{Rails.root}/screenshot.png
            #{Rails.root}/screenshot_0.png~
            #{Rails.root}/screenshot_1.png~
            at caller
          MSG
        end
      end
    end
  end
end
