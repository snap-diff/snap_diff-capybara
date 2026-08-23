# frozen_string_literal: true

require "test_helper"
require "snap_diff"
require "snap_diff/screenshot_assertion"

class DSLTest < ActiveSupport::TestCase
  include SnapDiff::DSL
  include DSLStub

  def before_setup
    @original_root = SnapDiff.config.root
    @new_root = Dir.mktmpdir
    SnapDiff.config.root = Pathname.new(@new_root)
    super
  end

  def after_teardown
    super
    SnapDiff.config.root = @original_root
    FileUtils.remove_entry(@new_root) if @new_root
  end

  test "#screenshot raises error when screenshot is missing and fail_if_new is true" do
    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      SnapDiff.config.stub(:fail_if_new, true) do
        assert_raises SnapDiff::ExpectationNotMet, match: /No existing screenshot found for/ do
          screenshot "not_existing_screenshot-name"
        end
      end
    end
  end

  # The reported figures are libvips': area_size and region come out as floats
  # and there is no max_color_distance. They used to be chunky_png's (629 /
  # [11,3,48,20] / max_color_distance 187.4) because a Comparison built without
  # an explicit `driver:` fell back to chunky_png -- 2.1 deleted that driver
  # and the selection that reached it, so this is the deletion showing through,
  # not a drift in the reporter.
  test "#assert_image_not_changed generates correct error message for image mismatch" do
    message = assert_image_not_changed(["my_test.rb:42"], "name", make_comparison(:a, :c, destination: "screenshot.png"))
    assert_equal <<~MSG.chomp, message
      Screenshot does not match for 'name': ({"area_size":684.0,"region":[11.0,3.0,49.0,21.0]})
      #{SnapDiff.config.root}/doc/screenshots/screenshot.png
      #{SnapDiff.config.root}/doc/screenshots/screenshot.base.diff.png
      #{SnapDiff.config.root}/doc/screenshots/screenshot.diff.png
      #{SnapDiff.config.root}/doc/screenshots/screenshot.heatmap.diff.png
      my_test.rb:42
    MSG
  end

  # Two tests are deleted rather than repointed:
  #
  # - "includes shift distance in error message": `shift_distance_limit` is
  #   implemented only by chunky_png and dies with it. libvips has no
  #   shift-distance comparison, so there is no equivalent message.
  # - "supports driver options for image comparison": there are no driver
  #   options left to support.

  test "#screenshot compares against the baseline and reports no difference" do
    assert_not screenshot("a")
  end

  def assert_no_screenshot_jobs_scheduled
    assert_not_predicate SnapDiff.session, :assertions_present?
  end

  test "#screenshot with skip_stack_frames: 0 includes our_screenshot in caller" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      assert_no_screenshot_jobs_scheduled

      snap = create_snapshot_for(:a, :c)

      our_screenshot(snap.full_name, 0)
      assert_equal 1, SnapDiff.session.assertions.size
      assert_match(/our_screenshot'/, SnapDiff.session.assertions[0].caller.first)
      assert_equal snap.full_name, SnapDiff.session.assertions[0].name
    end
  end

  test "#screenshot with skip_stack_frames: 1 includes test method in caller" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      assert_no_screenshot_jobs_scheduled

      snap = create_snapshot_for(:a, :c)

      our_screenshot(snap.full_name, 1)
      assert_equal 1, SnapDiff.session.assertions.size
      assert_match(
        %r{/dsl_test.rb},
        SnapDiff.session.assertions[0].caller.first
      )
      assert_equal snap.full_name, SnapDiff.session.assertions[0].name
    end
  end

  test "#assert_no_screenshot_changes reports caller from test method" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      assert_no_screenshot_jobs_scheduled

      snap = create_snapshot_for(:a, :c)

      assert_no_screenshot_changes(snap.full_name)
      assert_equal 1, SnapDiff.session.assertions.size
      assert_match(
        %r{/dsl_test.rb},
        SnapDiff.session.assertions[0].caller.first
      )
    end
  end

  test "#screenshot with delayed: false raises error when images differ" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff.config.stub(:delayed, false) do
        assert_raises(SnapDiff::ExpectationNotMet) do
          snap = create_snapshot_for(:c, :a)
          screenshot(snap.full_name, delayed: false)
        end
      end
    end
  end

  test "#screenshot with delayed: false succeeds when images match" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff.config.stub(:delayed, false) do
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
      assert_equal 1, SnapDiff.session.assertions.size
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
      assert_equal 1, SnapDiff.session.assertions.size
    end
  end

  test "#screenshot records new screenshots that have no baseline in the registry" do
    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      screenshot "a"

      assert_equal ["a"], SnapDiff.session.new_screenshots
    end
  end

  test "SnapDiff.reset clears new_screenshots" do
    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      screenshot "a"
      assert_predicate SnapDiff.session, :new_screenshots_present?

      SnapDiff.reset

      assert_not_predicate SnapDiff.session, :new_screenshots_present?
      assert_empty SnapDiff.session.new_screenshots
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

    SnapDiff.config.stub(:screenshoter, naive_screenshoter) do
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

  private

  def our_screenshot(name, skip_stack_frames)
    screenshot(name, skip_stack_frames: skip_stack_frames)
  end

  # Pins the user-facing error-message shape produced by #validate.
  def assert_image_not_changed(backtrace, name, comparison)
    assertion = SnapDiff::ScreenshotAssertion.new(name)
    assertion.caller = backtrace
    assertion.compare = comparison
    assertion.validate
  end
end
