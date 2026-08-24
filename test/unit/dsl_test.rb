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

  # "missing" means missing BASELINE (checkout_vcs false), not an unwritable
  # screenshot: the capture now runs before the raise (#260), so the name has
  # to be one ScreenshoterStub can actually produce -- it resolves "a_<digits>"
  # to the a.png fixture.
  test "#screenshot raises error when screenshot is missing and fail_if_new is true" do
    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      SnapDiff.config.stub(:fail_if_new, true) do
        assert_raises SnapDiff::ExpectationNotMet, match: /No existing screenshot found for/ do
          screenshot "a_#{Time.now.nsec}"
        end
      end
    end
  end

  test "#assert_image_not_changed generates correct error message for image mismatch" do
    message = assert_image_not_changed(["my_test.rb:42"], "name", make_comparison(:a, :c, destination: "screenshot.png"))
    value = (RUBY_VERSION >= "2.4") ? 187.4 : 188
    # Paths are relative to SnapDiff.config.root, and only the artifacts
    # that exist are listed: chunky_png produces no diff mask, so there is
    # no heatmap on disk for this comparison.
    assert_equal <<~MSG.chomp, message
      Screenshot does not match for 'name': the change spans 629 of 6400 px (9.83% of the 80x80 image)
        changed region: [11,3,48,20] (left,top,right,bottom edges)
        max color distance: #{value}
        judged against: no tolerance thresholds configured (any difference fails)
        baseline:           doc/screenshots/screenshot.base.png
        actual:             doc/screenshots/screenshot.png
        baseline annotated: doc/screenshots/screenshot.base.diff.png
        actual annotated:   doc/screenshots/screenshot.diff.png
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
      Screenshot does not match for 'name': the change spans 629 of 6400 px (9.83% of the 80x80 image)
        changed region: [11,3,48,20] (left,top,right,bottom edges)
        max color distance: #{value}
        max shift distance: 15 px
        judged against: shift_distance_limit 1
        baseline:           doc/screenshots/screenshot.base.png
        actual:             doc/screenshots/screenshot.png
        baseline annotated: doc/screenshots/screenshot.base.diff.png
        actual annotated:   doc/screenshots/screenshot.diff.png
      my_test.rb:42
    MSG
  end

  test "#screenshot supports driver options for image comparison" do
    skip "vips is disabled" unless defined?(Vips)
    assert_not screenshot("a", driver: :vips)
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

  # ADR-010: the per-screenshot `driver:` key is REMOVED in 2.1, so a user
  # who passes it has to hear about it -- and the DSL is how most of them
  # pass it. The message, once-per-process and silencing contracts are
  # proven in a subprocess by removed_in_2_1_deprecation_test; what THIS
  # example guards is the seam that test cannot reach, because the DSL
  # resolves `:driver` to a driver instance before Comparison ever sees the
  # hash. Asserting the routing, not the output: SnapDiff::Removal is
  # suppressed suite-wide (test_helper) and cannot be un-suppressed.
  test "#capture_screenshot routes a user's driver: option to the removal channel" do
    assert_includes removal_subjects_for(driver: :vips), :driver_setting
  end

  test "#capture_screenshot does not announce the driver removal when the user did not ask for one" do
    assert_not_includes removal_subjects_for, :driver_setting
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

  # --- the optional readiness block (#277a) -------------------------------
  #
  # Its justification is NOT ergonomics. A block can do nothing a line above
  # the call cannot -- while screenshots are ON. Its whole value is what
  # happens when they are OFF: both DSL methods return at the `active?`
  # guard, so a preceding `preload_all_images` (three browser round-trips in
  # a real consumer: scroll to bottom, an `assert_text` with its own wait,
  # scroll back) still runs and still costs, while the block does not run at
  # all. That is what makes "turn visual tests off" actually free rather
  # than free-except-for-the-scaffolding.
  #
  # The negative guard asserts a real side effect -- a counter the block
  # increments -- not a stub's call count: a stub that is never called and a
  # stub that was never wired up look identical.

  test "#assert_matches_screenshot does not run the readiness block when screenshots are disabled" do
    ran = 0
    SnapDiff.config.screenshot_enabled = false

    result = assert_matches_screenshot("c") { ran += 1 }

    assert_equal false, result
    assert_equal 0, ran, "the readiness block ran even though screenshots are disabled"
  end

  test "#capture_screenshot does not run the readiness block when screenshots are disabled" do
    ran = 0
    SnapDiff.config.screenshot_enabled = false

    result = capture_screenshot("c") { ran += 1 }

    assert_equal false, result
    assert_equal 0, ran, "the readiness block ran even though screenshots are disabled"
  end

  test "#screenshot does not run the readiness block when screenshots are disabled" do
    ran = 0
    SnapDiff.config.screenshot_enabled = false

    assert_not screenshot("c") { ran += 1 }
    assert_not screenshot("c", compare: false) { ran += 1 }

    assert_equal 0, ran, "the readiness block ran even though screenshots are disabled"
  end

  # Once, and before the capture. Ordering is asserted on the artifact the
  # capture produces rather than on a call count: the block looks for the
  # screenshot file, which cannot be there yet if the block really runs
  # first.
  test "#assert_matches_screenshot runs the readiness block exactly once, before the capture" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :c)
      snap.path.delete
      runs = 0
      captured_before_block = nil

      assert_matches_screenshot(snap.full_name) do
        runs += 1
        captured_before_block = snap.path.exist?
      end

      assert_equal 1, runs
      assert_equal false, captured_before_block, "the readiness block ran AFTER the capture"
      assert_predicate snap.path, :exist?
    end
  end

  test "#capture_screenshot runs the readiness block exactly once, before the capture" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :c)
      snap.path.delete
      runs = 0
      captured_before_block = nil

      capture_screenshot(snap.full_name) do
        runs += 1
        captured_before_block = snap.path.exist?
      end

      assert_equal 1, runs
      assert_equal false, captured_before_block, "the readiness block ran AFTER the capture"
      assert_predicate snap.path, :exist?
    end
  end

  # Once for the whole assertion, NOT once per stability attempt. If a
  # per-attempt need ever appears that is a separate decision, not a silent
  # behaviour change.
  test "#assert_matches_screenshot runs the readiness block once, not once per stability attempt" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a)
      runs = 0

      assert_matches_screenshot(snap.full_name, stability_time_limit: 0.01, wait: 1) { runs += 1 }

      assert_equal 1, runs
    end
  end

  # The block is the user's own code. A raise inside it is the user's error
  # and must arrive unwrapped, at its own class, with its own message.
  test "#assert_matches_screenshot lets an error from the readiness block through unchanged" do
    error = assert_raises(ArgumentError) do
      assert_matches_screenshot("c") { raise ArgumentError, "readiness blew up" }
    end

    assert_equal "readiness blew up", error.message
  end

  test "#capture_screenshot lets an error from the readiness block through unchanged" do
    error = assert_raises(ArgumentError) do
      capture_screenshot("c") { raise ArgumentError, "readiness blew up" }
    end

    assert_equal "readiness blew up", error.message
  end

  # `screenshot` and `assert_no_screenshot_changes` are pure delegators. A
  # block silently dropped on the way through is exactly the class of no-op
  # this release has spent its time eliminating.
  test "#screenshot forwards the readiness block down both of its branches" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      runs = 0

      screenshot(create_snapshot_for(:a, :c).full_name) { runs += 1 }
      screenshot(create_snapshot_for(:a, :c).full_name, compare: false) { runs += 1 }

      assert_equal 2, runs
    end
  end

  test "#assert_no_screenshot_changes forwards the readiness block" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      runs = 0

      assert_no_screenshot_changes(create_snapshot_for(:a, :c).full_name) { runs += 1 }

      assert_equal 1, runs
    end
  end

  private

  # Every removal subject the channel is asked to announce while the DSL
  # captures one screenshot with +options+.
  def removal_subjects_for(**options)
    subjects = []
    recorder = ->(subject, _message) { subjects << subject }

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff::Removal.stub(:warn_once, recorder) do
        # :c, like the other capture examples -- ScreenshoterStub copies the
        # like-named fixture, so the name has to be one that exists.
        capture_screenshot(:c, **options)
      end
    end

    subjects
  end

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
