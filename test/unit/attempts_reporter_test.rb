# frozen_string_literal: true

require "test_helper"
require "snap_diff"
# Not on any entry point's require path: stable_screenshoter pulls it in
# lazily, at the moment a capture actually goes unstable.
require "snap_diff/attempts_reporter"

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
      @manager = SnapDiff::SnapManager.new(SnapDiff.config.root / "attempts_reporter_test")
      @manager.create_output_directory_for
    end

    teardown do
      @manager.cleanup!
    end

    test "#generate returns the timeout message listing every attempt artifact" do
      snap = attempt_snapshot("unstable_message", %i[a b])

      message = AttemptsReporter.new(snap, {driver: :chunky_png}, {wait: 2, stability_time_limit: 0.1}).generate

      assert_match(/Could not get stable screenshot for 'unstable_message' within 2s \(2 attempts\)/, message)
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
      SnapDiff.config.stub(:screenshoter, alternating_screenshoter) do
        error = assert_raises(SnapDiff::UnstableImage) do
          StableScreenshoter
            .new({stability_time_limit: 0.05, wait: 0.2}, {driver: :chunky_png})
            .take_comparison_screenshot(snap)
        end
      end

      assert_match(/Could not get stable screenshot for 'unstable_end_to_end' within 0.2s/, error.message)

      attempts = snap.find_attempts_paths
      assert_operator attempts.size, :>=, 2, "the unstable run must leave its attempt artifacts for debugging"
      # Attempts after the first are overwritten with annotated diffs.
      annotated_attempt = Pathname.new(attempts.max)
      assert_not_equal (TEST_IMAGES_DIR / "a.png").binread, annotated_attempt.binread
      assert_not_equal (TEST_IMAGES_DIR / "b.png").binread, annotated_attempt.binread
    end

    # --- #271: name the region that would not settle -----------------
    #
    # The whole point of the message. A bare list of attempt paths made the
    # user open N images and eyeball them; faced with that, `sleep 2` wins
    # and the suite gets slower because diagnosis was hard.

    test "#generate names the one area that changed in every attempt and suggests masking it" do
      snap = painted_attempt_snapshot("ticker", [
        {[10, 10, 40, 30] => "#ff0000"},
        {[10, 10, 40, 30] => "#00ff00"},
        {[10, 10, 40, 30] => "#0000ff"},
        {[10, 10, 40, 30] => "#ffff00"}
      ])

      message = AttemptsReporter.new(snap, {driver: :chunky_png}, {wait: 2}).generate

      assert_match(/Could not get stable screenshot for 'ticker' within 2s \(4 attempts\)/, message)
      assert_match(/changed in 3 of 3 pairs/, message)
      assert_match(/Always the same area/, message)

      region = message[/The page kept changing in 1 area.*?\n\s*(\[[-\d,]+\])/m, 1]
      assert region, "the message must print the measured region:\n#{message}"
      # THE requirement: the suggested command carries the region actually
      # measured, never a coordinate invented for the prose.
      assert_includes message, %(skip_area: #{region})
      assert_includes message, %(assert_matches_screenshot "ticker", skip_area: #{region})
    end

    test "#generate reports areas that move around as churn and does NOT suggest skip_area" do
      snap = painted_attempt_snapshot("churn", [
        {},
        {[5, 5, 20, 20] => "#ff0000"},
        {[5, 5, 20, 20] => "#ff0000", [50, 50, 70, 70] => "#00ff00"},
        {[5, 5, 20, 20] => "#ff0000", [50, 50, 70, 70] => "#00ff00", [5, 50, 20, 70] => "#0000ff"}
      ])

      message = AttemptsReporter.new(snap, {driver: :chunky_png}, {wait: 2}).generate

      assert_match(/The page kept changing in 3 areas, over 3 attempt pairs/, message)
      assert_match(/Different areas at different times/, message)
      assert_match(/skip_area masks a fixed area and will not help here/, message)
      assert_no_match(/skip_area: \[/, message,
        "a region that only changed once is not an animation -- masking it would hide a real render")
    end

    test "#generate reports each area with its share of the image, in the #264 vocabulary" do
      snap = painted_attempt_snapshot("vocabulary", [
        {[0, 0, 40, 40] => "#ff0000"},
        {[0, 0, 40, 40] => "#00ff00"}
      ])

      message = AttemptsReporter.new(snap, {driver: :chunky_png}, {wait: 2}).generate

      assert_match(/\(left,top,right,bottom edges\)/, message)
      assert_match(/of the 80x80 image/, message)
      assert_match(/%/, message)
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

    # Builds a snapshot whose attempts are 80x80 white images with the given
    # rectangles painted on. One entry per attempt, oldest first; rectangles
    # are {[left, top, right, bottom] => "#rrggbb"}.
    def painted_attempt_snapshot(name, rectangles_per_attempt)
      @manager.snapshot(name).tap do |snap|
        rectangles_per_attempt.each do |rectangles|
          attempt_path = snap.next_attempt_path!
          FileUtils.mkdir_p(attempt_path.dirname)
          image = ChunkyPNG::Image.new(80, 80, ChunkyPNG::Color::WHITE)
          rectangles.each do |(left, top, right, bottom), color|
            image.rect(left, top, right, bottom, ChunkyPNG::Color::TRANSPARENT, ChunkyPNG::Color.from_hex(color))
          end
          image.save(attempt_path.to_s)
        end
      end
    end
  end
end
