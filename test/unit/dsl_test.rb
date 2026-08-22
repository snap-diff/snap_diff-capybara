# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff"
require "capybara_screenshot_diff/screenshot_assertion"

module CapybaraScreenshotDiff
  class DSLTest < ActiveSupport::TestCase
    include SnapDiff::DSL
    include CapybaraScreenshotDiff::DSLStub

    def before_setup
      @original_root = Capybara::Screenshot.root
      @new_root = Dir.mktmpdir
      Capybara::Screenshot.root = Pathname.new(@new_root)
      super
    end

    def after_teardown
      super
      Capybara::Screenshot.root = @original_root
      FileUtils.remove_entry(@new_root) if @new_root
    end

    test "#screenshot raises error when screenshot is missing and fail_if_new is true" do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        Capybara::Screenshot::Diff.stub(:fail_if_new, true) do
          assert_raises CapybaraScreenshotDiff::ExpectationNotMet, match: /No existing screenshot found for/ do
            screenshot "not_existing_screenshot-name"
          end
        end
      end
    end

    test "#assert_image_not_changed generates correct error message for image mismatch" do
      message = assert_image_not_changed(["my_test.rb:42"], "name", make_comparison(:a, :c, destination: "screenshot.png"))
      value = (RUBY_VERSION >= "2.4") ? 187.4 : 188
      assert_equal <<~MSG.chomp, message
        Screenshot does not match for 'name': ({"area_size":629,"region":[11,3,48,20],"max_color_distance":#{value}})
        #{Capybara::Screenshot.root}/doc/screenshots/screenshot.png
        #{Capybara::Screenshot.root}/doc/screenshots/screenshot.base.diff.png
        #{Capybara::Screenshot.root}/doc/screenshots/screenshot.diff.png
        #{Capybara::Screenshot.root}/doc/screenshots/screenshot.heatmap.diff.png
        my_test.rb:42
      MSG
    end

    test "#assert_image_not_changed includes shift distance in error message when specified" do
      message = assert_image_not_changed(
        ["my_test.rb:42"],
        "name",
        make_comparison(:a, :c, destination: "screenshot.png", shift_distance_limit: 1, driver: :chunky_png)
      )
      value = (RUBY_VERSION >= "2.4") ? 5.0 : 5
      assert_equal <<~MSG.chomp, message
        Screenshot does not match for 'name': ({"area_size":629,"region":[11,3,48,20],"max_color_distance":#{value},"max_shift_distance":15})
        #{Capybara::Screenshot.root}/doc/screenshots/screenshot.png
        #{Capybara::Screenshot.root}/doc/screenshots/screenshot.base.diff.png
        #{Capybara::Screenshot.root}/doc/screenshots/screenshot.diff.png
        #{Capybara::Screenshot.root}/doc/screenshots/screenshot.heatmap.diff.png
        my_test.rb:42
      MSG
    end

    test "#screenshot supports driver options for image comparison" do
      skip "vips is disabled" unless defined?(Vips)
      assert_not screenshot("a", driver: :vips)
    end

    def assert_no_screenshot_jobs_scheduled
      assert_not_predicate CapybaraScreenshotDiff.registry, :assertions_present?
    end

    test "#screenshot with skip_stack_frames: 0 includes our_screenshot in caller" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        assert_no_screenshot_jobs_scheduled

        snap = create_snapshot_for(:a, :c)

        our_screenshot(snap.full_name, 0)
        assert_equal 1, CapybaraScreenshotDiff.assertions.size
        assert_match(/our_screenshot'/, CapybaraScreenshotDiff.assertions[0].caller.first)
        assert_equal snap.full_name, CapybaraScreenshotDiff.assertions[0].name
      end
    end

    test "#screenshot with skip_stack_frames: 1 includes test method in caller" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        assert_no_screenshot_jobs_scheduled

        snap = create_snapshot_for(:a, :c)

        our_screenshot(snap.full_name, 1)
        assert_equal 1, CapybaraScreenshotDiff.assertions.size
        assert_match(
          %r{/dsl_test.rb},
          CapybaraScreenshotDiff.assertions[0].caller.first
        )
        assert_equal snap.full_name, CapybaraScreenshotDiff.assertions[0].name
      end
    end

    test "#assert_no_screenshot_changes reports caller from test method" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        assert_no_screenshot_jobs_scheduled

        snap = create_snapshot_for(:a, :c)

        assert_no_screenshot_changes(snap.full_name)
        assert_equal 1, CapybaraScreenshotDiff.assertions.size
        assert_match(
          %r{/dsl_test.rb},
          CapybaraScreenshotDiff.assertions[0].caller.first
        )
      end
    end

    test "#screenshot with delayed: false raises error when images differ" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        Capybara::Screenshot::Diff.stub(:delayed, false) do
          assert_raises(CapybaraScreenshotDiff::ExpectationNotMet) do
            snap = create_snapshot_for(:c, :a)
            screenshot(snap.full_name, delayed: false)
          end
        end
      end
    end

    test "#screenshot with delayed: false succeeds when images match" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        Capybara::Screenshot::Diff.stub(:delayed, false) do
          snap = create_snapshot_for(:a)
          assert_nothing_raised { screenshot(snap.full_name, delayed: false) }
        end
      end
    end

    test "#screenshot accepts skip_area and stability_time_limit options" do
      assert_not screenshot(:a, skip_area: [0, 0, 1, 1], stability_time_limit: 0.01)
    end

    test "#screenshot creates new screenshot file when it doesn't exist" do
      screenshot(:c)

      snap = SnapDiff::SnapManager.snapshot("c")
      assert_predicate snap.path, :exist?
    end

    # Regression for https://github.com/snap-diff/snap_diff-capybara/issues/191:
    # a user-defined #screenshot in the test class must not hijack the gem's internals.
    test "#assert_no_screenshot_changes ignores user-defined #screenshot" do
      def self.screenshot(*, **)
        @user_screenshot_called = true
      end

      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :c)

        assert_no_screenshot_changes(snap.full_name)
        assert_not @user_screenshot_called
        assert_equal 1, CapybaraScreenshotDiff.assertions.size
      end
    end

    test "#assert_matches_screenshot ignores user-defined #screenshot" do
      def self.screenshot(*, **)
        @user_screenshot_called = true
      end

      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :c)

        assert_matches_screenshot(snap.full_name)
        assert_not @user_screenshot_called
        assert_equal 1, CapybaraScreenshotDiff.assertions.size
      end
    end

    test "#screenshot records new screenshots that have no baseline in the registry" do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        screenshot "a"

        assert_equal ["a"], CapybaraScreenshotDiff.new_screenshots
      end
    end

    test "CapybaraScreenshotDiff.reset clears new_screenshots" do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        screenshot "a"
        assert_predicate CapybaraScreenshotDiff, :new_screenshots_present?

        CapybaraScreenshotDiff.reset

        assert_not_predicate CapybaraScreenshotDiff, :new_screenshots_present?
        assert_empty CapybaraScreenshotDiff.new_screenshots
      end
    end

    test "#capture_screenshot writes the file and registers no assertion" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        capture_screenshot(:c)

        snap = SnapDiff::SnapManager.snapshot("c")
        assert_predicate snap.path, :exist?
        assert_no_screenshot_jobs_scheduled
      end
    end

    test "#capture_screenshot creates the destination directory for nested names" do
      naive_screenshoter = Class.new do
        def initialize(_capture_options, _comparison_options)
        end

        def take_comparison_screenshot(snapshot)
          File.binwrite(snapshot.path, "png")
        end
      end

      Capybara::Screenshot::Diff.stub(:screenshoter, naive_screenshoter) do
        capture_screenshot("nested/dir/example")

        assert_predicate SnapDiff::SnapManager.snapshot("nested/dir/example").path, :exist?
      end
    end

    test "#capture_screenshot does not raise even when a differing baseline exists" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :c)

        assert_nothing_raised { capture_screenshot(snap.full_name) }
        assert_no_screenshot_jobs_scheduled
      end
    end

    test "#screenshot with compare: false captures without registering an assertion" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :c)
        snap.path.delete

        screenshot(snap.full_name, compare: false)

        assert_predicate snap.path, :exist?
        assert_no_screenshot_jobs_scheduled
      end
    end

    test "#assert_image_not_changed cleans up base image when images are identical" do
      comparison = make_comparison(:a, :a)
      assert_image_not_changed(["my_test.rb:42"], "name", comparison)
      assert_not comparison.base_image_path.exist?
    end

    test "#assert_image_not_changed keeps base image when images differ" do
      comparison = make_comparison(:a, :b)
      assert_image_not_changed(["my_test.rb:42"], "name", comparison)
      assert comparison.base_image_path.exist?, "base image should be kept for reporter"
    end

    private

    def our_screenshot(name, skip_stack_frames)
      screenshot(name, skip_stack_frames: skip_stack_frames)
    end

    def assert_image_not_changed(*args)
      SnapDiff::ScreenshotAssertion.assert_image_not_changed(*args)
    end
  end
end
