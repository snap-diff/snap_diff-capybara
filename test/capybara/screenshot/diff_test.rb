# frozen_string_literal: true

require "test_helper"

module Capybara
  module Screenshot
    class DiffTest < ActionDispatch::IntegrationTest
      setup do
        @orig_add_os_path = Capybara::Screenshot.add_os_path
        Capybara::Screenshot.add_os_path = true

        @orig_add_driver_path = Capybara::Screenshot.add_driver_path
        Capybara::Screenshot.add_driver_path = true

        @orig_window_size = Capybara::Screenshot.window_size
        Capybara::Screenshot.window_size = [80, 80]
      end

      include Capybara::Screenshot::Diff
      include Diff::TestHelper

      teardown do
        Capybara::Screenshot.add_os_path = @orig_add_os_path
        Capybara::Screenshot.add_driver_path = @orig_add_driver_path
        Capybara::Screenshot.window_size = @orig_window_size
      end

      def test_that_it_has_a_version_number
        refute_nil ::Capybara::Screenshot::Diff::VERSION
      end

      def test_screenshot_groups_are_replaced
        assert_nil @screenshot_group
        screenshot_group "a"
        assert_equal "a", @screenshot_group
        screenshot_group "b"
        assert_equal "b", @screenshot_group
      end

      def test_screenshot_section_is_prepended
        assert_nil @screenshot_section
        assert_nil @screenshot_group
        screenshot_section "a"
        assert_equal "a", @screenshot_section
        assert_match %r{doc/screenshots/rack_test/(macos|linux)/a}, screenshot_dir
        screenshot_group "b"
        assert_equal "b", @screenshot_group
        assert_match %r{doc/screenshots/rack_test/(macos|linux)/a/b}, screenshot_dir
        screenshot_group "c"
        assert_equal "c", @screenshot_group
        assert_match %r{doc/screenshots/rack_test/(macos|linux)/a/c}, screenshot_dir
      end

      test "screenshot" do
        screenshot_group "screenshot"
        screenshot "a"
      end

      def test_screenshot_with_alternate_save_path
        default_path = Capybara::Screenshot.save_path
        Capybara::Screenshot.save_path = "foo/bar"
        screenshot_section "a"
        screenshot_group "b"
        screenshot "a"
        assert_match %r{foo/bar/rack_test/(macos|linux)/a/b}, screenshot_dir
      ensure
        Capybara::Screenshot.save_path = default_path
      end

      def test_screenshot_with_stability_time_limit
        Capybara::Screenshot.stability_time_limit = 0.001
        screenshot "a"
      ensure
        Capybara::Screenshot.stability_time_limit = nil
      end

      def test_screenshot_with_color_threshold
        a_img = ChunkyPNG::Image.from_blob(File.binread("#{TEST_IMAGES_DIR}/a.png"))
        a_val = a_img[9, 14]
        a_img[9, 14] = a_val + 0x010000 + 0x000100 + 0x000001
        rev_filename = "#{Rails.root}/#{screenshot_dir}/a_0.png~"
        FileUtils.mkdir_p(File.dirname(rev_filename))
        a_img.save(rev_filename)

        screenshot "a", color_distance_limit: 3
      ensure
        File.delete(rev_filename) if File.exist?(rev_filename)
      end

      test "full_name" do
        assert_equal "a", full_name("a")
        screenshot_group "b"
        assert_equal "b/a", full_name("a")
        screenshot_section "c"
        assert_equal "c/b/a", full_name("a")
        screenshot_group nil
        assert_equal "c/a", full_name("a")
      end

      test "full_name allows symbol" do
        screenshot_group :b
        assert_equal "b/a", full_name(:a)
      end

      test "detect available diff drivers on the loading" do
        # NOTE for tests we are loading both drivers, so we expect that all of them are available
        assert_equal %i[vips chunky_png], Capybara::Screenshot::Diff::AVAILABLE_DRIVERS
      end
    end
  end
end
