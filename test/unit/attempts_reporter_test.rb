# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff"

module SnapDiff
  # Guard #2 from the v2 core-redesign acceptance contract (D8).
  #
  # The stability-failure path — unstable page -> UnstableImage raised ->
  # annotated diff artifacts on disk — had zero direct coverage: no test file
  # mentioned AttemptsReporter at all. These tests pin today's behavior
  # (raise from inside capture) before the redesign turns the failure into
  # data raised later at verify time.
  class AttemptsReporterTest < ActiveSupport::TestCase
    setup do
      @manager = SnapDiff::SnapManager.new(Capybara::Screenshot.root / "attempts_reporter_test")
      @manager.create_output_directory_for
    end

    teardown do
      @manager.cleanup!
    end

    test "#generate returns the timeout message listing every attempt artifact" do
      snap = attempt_snapshot("unstable_message", %i[a b])

      message = AttemptsReporter.new(snap, {driver: :chunky_png}, {wait: 2, stability_time_limit: 0.1}).generate

      assert_match(/Could not get stable screenshot within 2s/, message)
      snap.find_attempts_paths.each do |attempt_path|
        assert_includes message, attempt_path.to_s
      end
    end

    test "#generate overwrites later attempts with annotated diffs" do
      snap = attempt_snapshot("unstable_annotated", %i[a b])
      newest_attempt = Pathname.new(snap.find_attempts_paths.max)
      original_bytes = newest_attempt.binread

      AttemptsReporter.new(snap, {driver: :chunky_png}, {wait: 2, stability_time_limit: 0.1}).generate

      assert_predicate newest_attempt, :exist?
      assert_not_equal original_bytes, newest_attempt.binread,
        "each attempt after the first should be replaced by its annotated diff for debugging"
    end

    # End to end through StableScreenshoter: a page that never stabilizes
    # (every attempt differs from the previous one) times out, raises
    # UnstableImage from inside capture, and leaves annotated attempts behind.
    test "StableScreenshoter raises UnstableImage with annotated attempts when the page never stabilizes" do
      alternating_screenshoter = Class.new(SnapDiff::Screenshoter) do
        def take_screenshot(screenshot_path)
          @flip = !@flip
          FileUtils.mkdir_p(screenshot_path.dirname)
          FileUtils.cp(TEST_IMAGES_DIR / "#{@flip ? "a" : "b"}.png", screenshot_path)
        end
      end

      snap = @manager.snapshot("unstable_end_to_end")

      error = nil
      Capybara::Screenshot::Diff.stub(:screenshoter, alternating_screenshoter) do
        error = assert_raises(CapybaraScreenshotDiff::UnstableImage) do
          StableScreenshoter
            .new({stability_time_limit: 0.05, wait: 0.2}, {driver: :chunky_png})
            .take_comparison_screenshot(snap)
        end
      end

      assert_match(/Could not get stable screenshot within 0.2s/, error.message)

      attempts = snap.find_attempts_paths
      assert_operator attempts.size, :>=, 2, "the unstable run must leave its attempt artifacts for debugging"
      # Attempts after the first are overwritten with annotated diffs.
      annotated_attempt = Pathname.new(attempts.max)
      assert_not_equal (TEST_IMAGES_DIR / "a.png").binread, annotated_attempt.binread
      assert_not_equal (TEST_IMAGES_DIR / "b.png").binread, annotated_attempt.binread
    end

    private

    # Builds a snapshot with one attempt file per fixture, oldest first.
    def attempt_snapshot(name, fixtures)
      @manager.snapshot(name).tap do |snap|
        fixtures.each do |fixture|
          attempt_path = snap.next_attempt_path!
          FileUtils.mkdir_p(attempt_path.dirname)
          FileUtils.cp(fixture_image_path_from(fixture), attempt_path)
        end
      end
    end
  end
end
