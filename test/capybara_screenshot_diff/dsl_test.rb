# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff"
require "capybara_screenshot_diff/screenshot_assertion"

module CapybaraScreenshotDiff
  class DSLTest < ActionDispatch::IntegrationTest
    include CapybaraScreenshotDiff::DSL
    include CapybaraScreenshotDiff::DSLStub

    test "raise error on missing screenshot when fail_if_new is true" do
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, false) do
        Capybara::Screenshot::Diff.stub(:fail_if_new, true) do
          assert_raises CapybaraScreenshotDiff::ExpectationNotMet, match: /No existing screenshot found for/ do
            screenshot "not_existing_screenshot-name"
          end
        end
      end
    end

    def test_assert_image_not_changed
      message = assert_image_not_changed(["my_test.rb:42"], "name", make_comparison(:a, :c, destination: "screenshot.png"))
      value = (RUBY_VERSION >= "2.4") ? 187.4 : 188
      assert_equal <<~MSG.chomp, message
        Screenshot does not match for 'name': ({"area_size":629,"region":[11,3,48,20],"max_color_distance":#{value}})
        #{Rails.root}/doc/screenshots/screenshot.png
        #{Rails.root}/doc/screenshots/screenshot.base.diff.png
        #{Rails.root}/doc/screenshots/screenshot.diff.png
        #{Rails.root}/doc/screenshots/screenshot.heatmap.diff.png
        my_test.rb:42
      MSG
    end

    def test_assert_image_not_changed_with_shift_distance_limit
      message = assert_image_not_changed(
        ["my_test.rb:42"],
        "name",
        make_comparison(:a, :c, destination: "screenshot.png", shift_distance_limit: 1, driver: :chunky_png)
      )
      value = (RUBY_VERSION >= "2.4") ? 5.0 : 5
      assert_equal <<~MSG.chomp, message
        Screenshot does not match for 'name': ({"area_size":629,"region":[11,3,48,20],"max_color_distance":#{value},"max_shift_distance":15})
        #{Rails.root}/doc/screenshots/screenshot.png
        #{Rails.root}/doc/screenshots/screenshot.base.diff.png
        #{Rails.root}/doc/screenshots/screenshot.diff.png
        #{Rails.root}/doc/screenshots/screenshot.heatmap.diff.png
        my_test.rb:42
      MSG
    end

    def test_screenshot_support_drivers_options
      skip "vips is disabled" unless defined?(Capybara::Screenshot::Diff::Drivers::VipsDriverTest)
      assert_not screenshot("a", driver: :vips)
    end

    def assert_no_screenshot_jobs_scheduled
      assert_not_predicate CapybaraScreenshotDiff.registry, :assertions_present?
    end

    def test_skip_stack_frames
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, true) do
        assert_no_screenshot_jobs_scheduled

        snap = create_snapshot_for(:a, :c)

        our_screenshot(snap.full_name, 0)
        assert_equal 1, CapybaraScreenshotDiff.assertions.size
        assert_match(/our_screenshot'/, CapybaraScreenshotDiff.assertions[0].caller.first)
        assert_equal snap.full_name, CapybaraScreenshotDiff.assertions[0].name

        our_screenshot(snap.full_name, 1)
        assert_equal 2, CapybaraScreenshotDiff.assertions.size
        assert_match(
          %r{/dsl_test.rb:.*?test_skip_stack_frames},
          CapybaraScreenshotDiff.assertions[1].caller.first
        )
        assert_equal snap.full_name, CapybaraScreenshotDiff.assertions[1].name
      end
    end

    def test_inline_screenshot_assertion_validation_with_difference
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, true) do
        Capybara::Screenshot::Diff.stub(:delayed, false) do
          assert_raises(CapybaraScreenshotDiff::ExpectationNotMet) do
            snap = create_snapshot_for(:c, :a)
            screenshot(snap.full_name, delayed: false)
          end
        end
      end
    end

    def test_inline_screenshot_assertion_validation_without_difference
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, true) do
        Capybara::Screenshot::Diff.stub(:delayed, false) do
          snap = create_snapshot_for(:a)
          assert_nothing_raised { screenshot(snap.full_name, delayed: false) }
        end
      end
    end

    def test_skip_area_and_stability_time_limit
      assert_not screenshot(:a, skip_area: [0, 0, 1, 1], stability_time_limit: 0.01)
    end

    def test_creates_new_screenshot
      screenshot(:c)

      snap = CapybaraScreenshotDiff::SnapManager.snapshot("c")
      assert_predicate snap.path, :exist?
    end

    def test_cleanup_base_image_for_no_change
      comparison = make_comparison(:a, :a)
      assert_image_not_changed(["my_test.rb:42"], "name", comparison)
      assert_not comparison.base_image_path.exist?
    end

    def test_cleanup_base_image_for_changes
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
