# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff"
require "capybara_screenshot_diff/screenshot_assertion"

module CapybaraScreenshotDiff
  class DSLTest < ActiveSupport::TestCase
    include CapybaraScreenshotDiff::DSL
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
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, false) do
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
      skip "vips is disabled" unless defined?(Capybara::Screenshot::Diff::Drivers::VipsDriverTest)
      assert_not screenshot("a", driver: :vips)
    end

    def assert_no_screenshot_jobs_scheduled
      assert_not_predicate CapybaraScreenshotDiff.registry, :assertions_present?
    end

    test "#screenshot with skip_stack_frames: 0 includes our_screenshot in caller" do
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, true) do
        assert_no_screenshot_jobs_scheduled

        snap = create_snapshot_for(:a, :c)

        our_screenshot(snap.full_name, 0)
        assert_equal 1, CapybaraScreenshotDiff.assertions.size
        assert_match(/our_screenshot'/, CapybaraScreenshotDiff.assertions[0].caller.first)
        assert_equal snap.full_name, CapybaraScreenshotDiff.assertions[0].name
      end
    end

    test "#screenshot with skip_stack_frames: 1 includes test method in caller" do
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, true) do
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

    test "#screenshot with delayed: false raises error when images differ" do
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, true) do
        Capybara::Screenshot::Diff.stub(:delayed, false) do
          assert_raises(CapybaraScreenshotDiff::ExpectationNotMet) do
            snap = create_snapshot_for(:c, :a)
            screenshot(snap.full_name, delayed: false)
          end
        end
      end
    end

    test "#screenshot with delayed: false succeeds when images match" do
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, true) do
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

      snap = CapybaraScreenshotDiff::SnapManager.snapshot("c")
      assert_predicate snap.path, :exist?
    end

    test "#assert_image_not_changed cleans up base image when images are identical" do
      comparison = make_comparison(:a, :a)
      assert_image_not_changed(["my_test.rb:42"], "name", comparison)
      assert_not comparison.base_image_path.exist?
    end

    test "#assert_image_not_changed cleans up base image when images differ" do
      comparison = make_comparison(:a, :b)
      assert_image_not_changed(["my_test.rb:42"], "name", comparison)
      assert_not comparison.base_image_path.exist?
    end

    private

    def our_screenshot(name, skip_stack_frames)
      screenshot(name, skip_stack_frames: skip_stack_frames)
    end

    def assert_image_not_changed(*args)
      CapybaraScreenshotDiff::ScreenshotAssertion.assert_image_not_changed(*args)
    end
  end
end
