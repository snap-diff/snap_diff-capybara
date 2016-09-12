require 'test_helper'

module Capybara
  module Screenshot
    class DiffTest < ActionDispatch::IntegrationTest
      setup do
        Capybara::Screenshot.add_os_path = true
        Capybara::Screenshot.add_driver_path = true
        Capybara::Screenshot.window_size = [80, 80]
      end

      def test_that_it_has_a_version_number
        refute_nil ::Capybara::Screenshot::Diff::VERSION
      end

      def test_screenshot_groups_are_replaced
        assert_equal nil, @screenshot_group
        screenshot_group 'a'
        assert_equal 'a', @screenshot_group
        screenshot_group 'b'
        assert_equal 'b', @screenshot_group
      end

      def test_screenshot_section_is_prepended
        assert_equal nil, @screenshot_section
        assert_equal nil, @screenshot_group
        screenshot_section 'a'
        assert_equal 'a', @screenshot_section
        assert_match %r{doc/screenshots/rack_test/(macos|linux)/a}, screenshot_dir
        screenshot_group 'b'
        assert_equal 'b', @screenshot_group
        assert_match %r{doc/screenshots/rack_test/(macos|linux)/a/b}, screenshot_dir
        screenshot_group 'c'
        assert_equal 'c', @screenshot_group
        assert_match %r{doc/screenshots/rack_test/(macos|linux)/a/c}, screenshot_dir
      end

      test 'screenshot' do
        screenshot_group 'screenshot'
        screenshot 'a'
      end

      def test_screenshot_with_stability_time_limit
        Capybara::Screenshot.stability_time_limit = 0.001
        screenshot 'a'
      ensure
        Capybara::Screenshot.stability_time_limit = nil
      end

      test 'full_name' do
        assert_equal 'a', full_name('a')
        screenshot_group 'b'
        assert_equal 'b/a', full_name('a')
        screenshot_section 'c'
        assert_equal 'c/b/a', full_name('a')
        screenshot_group nil
        assert_equal 'c/a', full_name('a')
      end

      test 'full_name allows symbol' do
        screenshot_group :b
        assert_equal 'b/a', full_name(:a)
      end
    end
  end
end
