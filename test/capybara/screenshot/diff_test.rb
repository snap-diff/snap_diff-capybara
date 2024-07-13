# frozen_string_literal: true

require "test_helper"
require "minitest/stub_const"
require "support/non_minitest_assertions"

module Capybara
  module Screenshot
    class DiffTest < ActionDispatch::IntegrationTest
      setup do
        @orig_add_driver_path = Capybara::Screenshot.add_driver_path
        Capybara::Screenshot.add_driver_path = true

        @orig_add_os_path = Capybara::Screenshot.add_os_path
        Capybara::Screenshot.add_os_path = true

        @orig_screenshot_format = Capybara::Screenshot.screenshot_format

        @orig_window_size = Capybara::Screenshot.window_size
        Capybara::Screenshot.window_size = [80, 80]
      end

      include Capybara::Screenshot::Diff
      include CapybaraScreenshotDiff::Minitest::Assertions
      include Diff::TestMethodsStub

      teardown do
        FileUtils.rm_rf Capybara::Screenshot.screenshot_area_abs

        Capybara::Screenshot.add_driver_path = @orig_add_driver_path
        Capybara::Screenshot.add_os_path = @orig_add_os_path
        Capybara::Screenshot.screenshot_format = @orig_screenshot_format
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
        assert_match %r{doc/screenshots/(macos|linux)/rack_test/a}, screenshot_dir
        screenshot_group "b"
        assert_equal "b", @screenshot_group
        assert_match %r{doc/screenshots/(macos|linux)/rack_test/a/b}, screenshot_dir
        screenshot_group "c"
        assert_equal "c", @screenshot_group
        assert_match %r{doc/screenshots/(macos|linux)/rack_test/a/c}, screenshot_dir
      end

      test "screenshot" do
        screenshot_group "screenshot"
        screenshot "a"
      end

      test "succeed on screenshot diff when fail_on_difference is false" do
        Capybara::Screenshot::Diff.stub(:fail_on_difference, false) do
          test_case = SampleMiniTestCase.new(:_test_sample_screenshot_error)
          test_case.run
          assert_equal 0, test_case.failures.size
        end
      end

      def test_screenshot_with_alternate_save_path
        default_path = Capybara::Screenshot.save_path
        Capybara::Screenshot.save_path = "foo/bar"
        screenshot_section "a"
        screenshot_group "b"
        screenshot "a"
        assert_match %r{foo/bar/(macos|linux)/rack_test/a/b}, screenshot_dir
      ensure
        Capybara::Screenshot.save_path = default_path
      end

      def test_screenshot_with_stability_time_limit
        Capybara::Screenshot.stability_time_limit = 0.001
        screenshot "a"
      ensure
        Capybara::Screenshot.stability_time_limit = nil
      end

      test "build_full_name" do
        assert_equal "a", build_full_name("a")
        screenshot_group "b"
        assert_equal "b/00_a", build_full_name("a")
        screenshot_section "c"
        assert_equal "c/b/01_a", build_full_name("a")
        screenshot_group nil
        assert_equal "c/a", build_full_name("a")
      end

      test "build_full_name allows symbol" do
        screenshot_group :b
        assert_equal "b/00_a", build_full_name(:a)
      end

      test "detect available diff drivers on the loading" do
        # NOTE for tests we are loading both drivers, so we expect that all of them are available
        expected_drivers = if defined?(Vips)
          %i[vips chunky_png]
        else
          %i[chunky_png]
        end
        assert_equal expected_drivers, Capybara::Screenshot::Diff::AVAILABLE_DRIVERS
      end

      test "aggregates failures instead of raising errors on teardown for Minitest" do
        test_case = SampleMiniTestCase.new(:_test_sample_screenshot_error)

        test_case.run

        assert_equal 1, test_case.failures.size
        assert_includes test_case.failures.first.message, "expected error message"
      end

      test "raising errors on teardown for non Minitest" do
        test_case = SampleNotMiniTestCase.new
        test_case._test_sample_screenshot_error

        expected_message =
          "Screenshot does not match for 'sample_screenshot' expected error message for non minitest"
        assert_raises(::StandardError, expected_message) { test_case.teardown }
        assert_empty(test_case.instance_variable_get(:@test_screenshots))
      end

      class SampleMiniTestCase < ActionDispatch::IntegrationTest
        include Capybara::Screenshot::Diff
        include CapybaraScreenshotDiff::Minitest::Assertions

        # NOTE: we need to add `_` as prefix to skip this test from auto-run
        def _test_sample_screenshot_error
          mock = ::Minitest::Mock.new
          mock.expect(:different?, true)
          mock.expect(:base_image_path, Pathname.new("screenshot.base.png"))
          mock.expect(:error_message, "expected error message")

          @test_screenshots = []
          @test_screenshots << ["my_test.rb:42", "sample_screenshot", mock]
          mock.expect(:clear_screenshots, @test_screenshots)
        end
      end

      class SampleNotMiniTestCase
        def self.setup
          # noop
        end

        def self.teardown(&block)
          @@teardown_callback = block
        end

        def teardown
          instance_eval(&@@teardown_callback) if @@teardown_callback
          @@teardown_callback = nil
        end

        include Capybara::Screenshot::Diff
        include CapybaraScreenshotDiff::NonMinitest::Assertions

        def _test_sample_screenshot_error
          comparison = ::Minitest::Mock.new
          comparison.expect(:different?, true)
          comparison.expect(:base_image_path, Pathname.new("screenshot.base.png"))
          comparison.expect(:error_message, "expected error message for non minitest")

          @test_screenshots << ["my_test.rb:42", "sample_screenshot", comparison]
        end
      end

      class ScreenshotFormatTest < ActionDispatch::IntegrationTest
        setup do
          @orig_screenshot_format = Capybara::Screenshot.screenshot_format
        end

        include Capybara::Screenshot::Diff
        include Diff::TestMethodsStub
        include CapybaraScreenshotDiff::Minitest::Assertions

        teardown do
          Capybara::Screenshot.screenshot_format = @orig_screenshot_format
        end

        test "use default screenshot format" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
          set_test_images("a.webp", :a, :a)

          Capybara::Screenshot.stub(:screenshot_format, "webp") do
            screenshot "a", driver: :vips

            assert_stored_screenshot("a.webp")
          end
        end

        test "override default screenshot format" do
          set_test_images("a.png", :a, :a)

          Capybara::Screenshot.stub(:screenshot_format, "webp") do
            screenshot "a", screenshot_format: "png"

            assert_stored_screenshot("a.png")
          end
        end
      end
    end
  end
end
