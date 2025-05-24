# frozen_string_literal: true

require "test_helper"
require "minitest/stub_const"
require "support/non_minitest_assertions"

module Capybara
  module Screenshot
    class DiffTest < ActionDispatch::IntegrationTest
      setup do
        Capybara.current_driver = Capybara.default_driver

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
      include CapybaraScreenshotDiff::DSLStub

      teardown do
        CapybaraScreenshotDiff::SnapManager.cleanup! unless persist_comparisons?
        CapybaraScreenshotDiff.reset

        Capybara::Screenshot.add_driver_path = @orig_add_driver_path
        Capybara::Screenshot.add_os_path = @orig_add_os_path
        Capybara::Screenshot.screenshot_format = @orig_screenshot_format
        Capybara::Screenshot.window_size = @orig_window_size
      end

      def test_that_it_has_a_version_number
        refute_nil ::Capybara::Screenshot::Diff::VERSION
      end

      def test_screenshot_groups_are_replaced
        assert_nil screenshot_namer.group
        screenshot_group "a"
        assert_equal "a", screenshot_namer.group
        screenshot_group "b"
        assert_equal "b", screenshot_namer.group
      end

      def test_screenshot_section_is_prepended
        assert_nil screenshot_namer.section
        assert_nil screenshot_namer.group

        screenshot_section "a"
        assert_equal "a", screenshot_namer.section
        assert_match %r{doc/screenshots/(macos|linux)/rack_test/a}, screenshot_dir

        screenshot_group "b"
        assert_equal "b", screenshot_namer.group
        assert_match %r{doc/screenshots/(macos|linux)/rack_test/a/b}, screenshot_dir

        screenshot_group "c"
        assert_equal "c", screenshot_namer.group
        assert_match %r{doc/screenshots/(macos|linux)/rack_test/a/c}, screenshot_dir
      end

      test "screenshot" do
        screenshot_group "screenshot"
        assert_matches_screenshot "a"
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
        assert_equal "c/b/00_a", build_full_name("a")
        screenshot_group nil
        assert_equal "c/a", build_full_name("a")
      end

      test "build_full_name allows symbol" do
        screenshot_group :b
        assert_equal "b/00_a", build_full_name(:a)
      end

      test "detect available diff drivers on the loading" do
        # NOTE for tests we are loading both drivers, so we expect that all of them are available
        expected_drivers = defined?(Vips) ? %i[vips chunky_png] : %i[chunky_png]

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
        assert_raises(CapybaraScreenshotDiff::ExpectationNotMet, expected_message) { test_case.teardown }
        assert_empty(CapybaraScreenshotDiff.assertions)
      end

      class SampleMiniTestCase < ActionDispatch::IntegrationTest
        include Capybara::Screenshot::Diff
        include CapybaraScreenshotDiff::Minitest::Assertions

        # NOTE: we need to add `_` as prefix to skip this test from auto-run
        def _test_sample_screenshot_error
          mock = ::Minitest::Mock.new
          mock.expect(:different?, true)
          mock.expect(:different?, true)
          mock.expect(:dimensions_changed?, false)
          mock.expect(:base_image_path, Pathname.new("screenshot.base.png"))
          mock.expect(:error_message, "expected error message")

          assertion = CapybaraScreenshotDiff::ScreenshotAssertion.from([["my_test.rb:42"], "sample_screenshot", mock])
          CapybaraScreenshotDiff.add_assertion(assertion)

          assert true
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
        ensure
          @@teardown_callback = nil
          CapybaraScreenshotDiff.reset
        end

        include Capybara::Screenshot::Diff
        include CapybaraScreenshotDiff::NonMinitest::Assertions

        def _test_sample_screenshot_error
          comparison = ::Minitest::Mock.new
          comparison.expect(:different?, true) # to find backtrace
          comparison.expect(:different?, true) # to find messages
          comparison.expect(:dimensions_changed?, false)
          comparison.expect(:base_image_path, Pathname.new("screenshot.base.png"))
          comparison.expect(:error_message, "expected error message for non minitest")

          assertion = CapybaraScreenshotDiff::ScreenshotAssertion.from([["my_test.rb:42"], "sample_screenshot", comparison])
          CapybaraScreenshotDiff.add_assertion(assertion)
        end
      end

      class ScreenshotFormatTest < ActionDispatch::IntegrationTest
        setup do
          @orig_screenshot_format = Capybara::Screenshot.screenshot_format
        end

        include Capybara::Screenshot::Diff
        include CapybaraScreenshotDiff::DSLStub
        include CapybaraScreenshotDiff::Minitest::Assertions

        teardown do
          Capybara::Screenshot.screenshot_format = @orig_screenshot_format
        end

        test "use default screenshot format" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
          snap = CapybaraScreenshotDiff::SnapManager.snapshot("a", "webp")

          set_test_images(snap, :a, :a)

          Capybara::Screenshot.stub(:screenshot_format, "webp") do
            screenshot "a", driver: :vips

            assert_stored_screenshot("a.webp")
          end
        end

        test "override default screenshot format" do
          snap = CapybaraScreenshotDiff::SnapManager.snapshot("a", "png")
          set_test_images(snap, :a, :a)

          Capybara::Screenshot.stub(:screenshot_format, "webp") do
            screenshot "a", screenshot_format: "png"

            assert_stored_screenshot("a.png")
          end
        end
      end

      def screenshot_dir
        screenshot_namer.current_group_directory
      end

      def screenshot_namer
        CapybaraScreenshotDiff.screenshot_namer
      end

      def build_full_name(name)
        CapybaraScreenshotDiff.screenshot_namer.full_name(name)
      end
    end
  end
end
