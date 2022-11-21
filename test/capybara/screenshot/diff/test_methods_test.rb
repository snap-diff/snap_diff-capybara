# frozen_string_literal: true

require "test_helper"

module Capybara
  module Screenshot
    module Diff
      class TestMethodsTest < ActionDispatch::IntegrationTest
        include TestMethods
        include TestHelper

        def test_assert_image_not_changed
          message = assert_image_not_changed("caller", "name", make_comparison(:a, :c))
          value = (RUBY_VERSION >= "2.4") ? 187.4 : 188
          assert_equal <<-MSG.strip_heredoc.chomp, message
            Screenshot does not match for 'name' ({"area_size":629,"region":[11,3,48,20],"max_color_distance":#{value}})
            #{Rails.root}/doc/screenshots/screenshot.png
            #{Rails.root}/doc/screenshots/screenshot.committed.png
            #{Rails.root}/doc/screenshots/screenshot.latest.png
            at caller
          MSG
        end

        def test_assert_image_not_changed_with_shift_distance_limit
          message =
            assert_image_not_changed("caller", "name", make_comparison(:a, :c, shift_distance_limit: 1, driver: :chunky_png))
          value = (RUBY_VERSION >= "2.4") ? 5.0 : 5
          assert_equal <<-MSG.strip_heredoc.chomp, message
            Screenshot does not match for 'name' ({"area_size":629,"region":[11,3,48,20],"max_color_distance":#{value},"max_shift_distance":15})
            #{Rails.root}/doc/screenshots/screenshot.png
            #{Rails.root}/doc/screenshots/screenshot.committed.png
            #{Rails.root}/doc/screenshots/screenshot.latest.png
            at caller
          MSG
        end

        def test_screenshot_support_drivers_options
          skip 'vips is disabled' unless defined?(Capybara::Screenshot::Diff::Drivers::VipsDriverTest)
          screenshot("a", driver: :vips)
        end

        def test_skip_stack_frames
          assert_nil @test_screenshots
          make_comparison(:a, :c, name: "a")

          our_screenshot("a", 0)
          assert_equal 1, @test_screenshots.size
          assert_match(/test_methods_test.rb:\d+:in `our_screenshot'/, @test_screenshots[0][0])
          assert_equal "a", @test_screenshots[0][1]

          our_screenshot("a", 1)
          assert_equal 2, @test_screenshots.size
          assert_match(/test_methods_test.rb:\d+:in `test_skip_stack_frames'/, @test_screenshots[1][0])
          assert_equal "a", @test_screenshots[1][1]
        end

        def test_skip_area_and_stability_time_limit
          screenshot(:a, skip_area: [0, 0, 1, 1], stability_time_limit: 0.01)
        end

        private

        def our_screenshot(name, skip_stack_frames)
          screenshot(name, skip_stack_frames: skip_stack_frames)
        end
      end
    end
  end
end
