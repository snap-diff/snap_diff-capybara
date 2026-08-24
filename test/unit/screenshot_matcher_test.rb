# frozen_string_literal: true

require "test_helper"
require "snap_diff"

# Guard #1 from the v2 core-redesign acceptance contract: pins
# ScreenshotMatcher's current external behavior (D1-D4) in isolation
# before the orchestration middle is redesigned. Until now the class had
# no dedicated unit test at all — it was exercised only indirectly
# through dsl_test stubs and full-browser integration tests.
class ScreenshotMatcherTest < ActiveSupport::TestCase
  include DSLStub

  # A screenshoter probe that records the (capture_options,
  # comparison_options) split it was built with (D1) and writes a real
  # file so the rest of the flow proceeds.
  def recording_screenshoter(calls)
    Class.new do
      define_method(:initialize) do |capture_options, comparison_options|
        calls << [capture_options, comparison_options]
      end

      def take_comparison_screenshot(snapshot)
        snapshot.path.dirname.mkpath
        FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), snapshot.path)
      end
    end
  end

  # D4: dual return shape — nil for the new-screenshot path, after
  # side-effecting record_new_screenshot into the registry.
  test "#build_screenshot_assertion returns nil and records a new screenshot when no baseline exists" do
    # ScreenshoterStub resolves "c_<digits>" to the c.png fixture.
    name = "c_#{Time.now.nsec}"

    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      assertion = SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion

      assert_nil assertion
      assert_includes SnapDiff.session.new_screenshots, name
      assert_predicate SnapDiff::SnapManager.path_for(name).path, :exist?,
        "the screenshot is still captured on the new-screenshot path"
    end
  end

  # D4: the other return shape — a fully wired ScreenshotAssertion.
  test "#build_screenshot_assertion returns an assertion with compare and caller when a baseline exists" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :c)

      assertion = SnapDiff::ScreenshotMatcher.new(snap.full_name).build_screenshot_assertion

      assert_instance_of SnapDiff::ScreenshotAssertion, assertion
      assert_equal snap.full_name, assertion.name
      assert_kind_of Array, assertion.caller
      assert_match(/screenshot_matcher_test\.rb/, assertion.caller.first)
      assert_equal snap.path, assertion.compare.image_path
      assert_equal snap.base_path, assertion.compare.base_image_path
    end
  end

  # D1: the one-hash-carved-into-two option split. Stability/wait/crop
  # are deleted into capture options; whatever is left over becomes the
  # comparison options.
  test "#build_screenshot_assertion splits capture options from comparison options" do
    calls = []

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff.config.stub(:screenshoter, recording_screenshoter(calls)) do
        snap = create_snapshot_for(:a, :c)

        SnapDiff::ScreenshotMatcher.new(snap.full_name, tolerance: 0.03, wait: 5).build_screenshot_assertion
      end
    end

    assert_equal 1, calls.size
    capture_options, comparison_options = calls.first

    assert_equal 5, capture_options[:wait]
    assert_nil capture_options[:stability_time_limit]
    assert_includes capture_options, :crop
    assert_includes capture_options, :screenshot_format

    assert_equal 0.03, comparison_options[:tolerance]
    assert_not_includes comparison_options, :wait, "wait must be carved out of comparison options"
    assert_not_includes comparison_options, :stability_time_limit
    assert_not_includes comparison_options, :crop
  end

  # D1 (fixed): the split is a pure partition — the input hash survives
  # untouched. The frozen input would raise FrozenError under the old
  # delete-based carve.
  test "#extract_capture_and_comparison_options does not mutate the input options" do
    matcher = SnapDiff::ScreenshotMatcher.new("a")
    options = {tolerance: 0.03, wait: 5, crop: [0, 0, 2, 2], stability_time_limit: 1}.freeze

    capture_options, comparison_options = matcher.send(:extract_capture_and_comparison_options, options)

    assert_equal 5, capture_options[:wait]
    assert_not_includes comparison_options, :wait
    assert_equal({tolerance: 0.03, wait: 5, crop: [0, 0, 2, 2], stability_time_limit: 1}, options)
  end

  # D2: screenshoter selection is by hash-key presence — no
  # :stability_time_limit means the configured plain screenshoter.
  test "#build_screenshot_assertion uses the configured screenshoter without stability_time_limit" do
    calls = []

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff.config.stub(:screenshoter, recording_screenshoter(calls)) do
        snap = create_snapshot_for(:a, :c)
        SnapDiff::ScreenshotMatcher.new(snap.full_name).build_screenshot_assertion
      end
    end

    assert_equal 1, calls.size, "the configured plain screenshoter must take the shot"
  end

  # D2: presence of :stability_time_limit switches to StableScreenshoter.
  test "#build_screenshot_assertion uses StableScreenshoter when stability_time_limit is present" do
    stable_calls = []
    fake_stable = Object.new
    def fake_stable.take_comparison_screenshot(snapshot)
      snapshot.path.dirname.mkpath
      FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), snapshot.path)
    end

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff::StableScreenshoter.stub(:new, lambda { |capture_options, comparison_options|
        stable_calls << [capture_options, comparison_options]
        fake_stable
      }) do
        snap = create_snapshot_for(:a, :c)
        SnapDiff::ScreenshotMatcher.new(snap.full_name, stability_time_limit: 0.1, wait: 1).build_screenshot_assertion
      end
    end

    assert_equal 1, stable_calls.size
    assert_equal 0.1, stable_calls.first.first[:stability_time_limit]
  end

  # The raise-only window-size guard (relocated in the redesign into
  # Capture::Viewport#prepare!): wrong window size fails fast, before
  # any capture.
  test "#build_screenshot_assertion raises WindowSizeMismatchError when the window size is wrong" do
    SnapDiff::BrowserHelpers.stub(:window_size_is_wrong?, true) do
      SnapDiff::BrowserHelpers.stub(:selenium?, false) do
        assert_raises(SnapDiff::WindowSizeMismatchError) do
          SnapDiff::ScreenshotMatcher.new("matcher_window_size").build_screenshot_assertion
        end
      end
    end

    refute SnapDiff::SnapManager.path_for("matcher_window_size").path.exist?,
      "no screenshot may be written when the window size is wrong"
  end

  # Same guard on the compare-free #capture path.
  test "#capture raises WindowSizeMismatchError when the window size is wrong" do
    SnapDiff::BrowserHelpers.stub(:window_size_is_wrong?, true) do
      SnapDiff::BrowserHelpers.stub(:selenium?, false) do
        assert_raises(SnapDiff::WindowSizeMismatchError) do
          SnapDiff::ScreenshotMatcher.new("matcher_window_size").capture
        end
      end
    end

    refute SnapDiff::SnapManager.path_for("matcher_window_size").path.exist?,
      "no screenshot may be written when the window size is wrong"
  end

  # Pins ScreenshotMatcher's viewport-preparation cadence: exactly one
  # window-size check per capture, before the screenshoter runs. The
  # stable screenshoter is stubbed here, so this guard does not police
  # the real retry loop — that it stays check-free is verified by
  # reading (no window-size calls in stable_screenshoter.rb).
  test "window size is checked exactly once per capture even when stability retries happen" do
    checks = 0
    fake_stable = Object.new
    def fake_stable.take_comparison_screenshot(snapshot)
      # Simulates a stability loop that needed several attempts; nothing
      # here may trigger another window-size check.
      2.times { snapshot.next_attempt_path! }
      snapshot.path.dirname.mkpath
      FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), snapshot.path)
    end

    SnapDiff::BrowserHelpers.stub(:window_size_is_wrong?, proc { |_expected|
      checks += 1
      false
    }) do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        SnapDiff::StableScreenshoter.stub(:new, ->(*, **) { fake_stable }) do
          snap = create_snapshot_for(:a, :c)
          SnapDiff::ScreenshotMatcher.new(snap.full_name, stability_time_limit: 0.1, wait: 1).build_screenshot_assertion
        end
      end
    end

    assert_equal 1, checks
  end

  # #capture is the compare-free path: file written, no assertion built,
  # nothing recorded in the registry.
  test "#capture writes the screenshot without touching the registry" do
    # ScreenshoterStub resolves "b_<digits>" to the b.png fixture.
    name = "b_#{Time.now.nsec}"

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff::ScreenshotMatcher.new(name).capture

      assert_predicate SnapDiff::SnapManager.path_for(name).path, :exist?
      assert_not_predicate SnapDiff.session, :assertions_present?
      assert_empty SnapDiff.session.new_screenshots
    end
  end

  # --- THE FALSE GREEN -------------------------------------------------
  #
  # Baselines are read from git (`git show HEAD:<path>`), never from disk,
  # and `fail_if_new` is false off CI by design. So a screenshot with no
  # COMMITTED baseline is not compared at all: no assertion is registered,
  # the test passes whatever the page looks like, and the capture silently
  # overwrites the PNG that was sitting on disk. That is the product's core
  # promise failing quietly, in the default local configuration, for every
  # new user -- it has to be said out loud.

  test "#build_screenshot_assertion warns when nothing was compared for lack of a committed baseline" do
    name = "c_#{Time.now.nsec}"
    path = SnapDiff::SnapManager.path_for(name).path

    _out, err = capture_io do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
      end
    end

    assert_match(/No committed baseline/, err)
    assert_includes err, path.to_s, "the warning must name the real screenshot, not the .base temp file"
    assert_no_match(/\.base\.png/, err)
    assert_match(/[Cc]ommit/, err, "the warning must say what to do about it")
    # The check has to run BEFORE the capture, or every screenshot looks
    # like it already had a file sitting there.
    assert_no_match(/already there/, err)
  end

  test "#build_screenshot_assertion warns once per screenshot, not once per run" do
    name = "c_#{Time.now.nsec}"

    _out, err = capture_io do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        2.times { SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion }
      end
    end

    assert_equal 1, err.scan("No committed baseline").size, err
  end

  # The genuinely confusing case: the user SEES a PNG in doc/screenshots and
  # assumes it is the baseline. It is not one until it is committed.
  test "#build_screenshot_assertion flags an uncommitted screenshot already on disk" do
    name = "c_#{Time.now.nsec}"
    path = SnapDiff::SnapManager.path_for(name).path
    path.dirname.mkpath
    FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), path)

    _out, err = capture_io do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
      end
    end

    assert_match(/not a baseline until it is committed/, err)
  end

  test "#build_screenshot_assertion stays quiet when a committed baseline exists" do
    _out, err = capture_io do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :c)
        SnapDiff::ScreenshotMatcher.new(snap.full_name).build_screenshot_assertion
      end
    end

    assert_no_match(/No committed baseline/, err)
  end

  # The other half of the same message. It used to name `<...>.base.png` (a
  # generated temp file nobody creates or commits), promise
  # `RECORD_SCREENSHOTS=1`, which nothing in lib/ has ever read, and point at
  # the legacy namespace in the release whose headline is SnapDiff.
  test "the fail_if_new error tells the truth about the file and the fix" do
    name = "c_#{Time.now.nsec}"
    path = SnapDiff::SnapManager.path_for(name).path

    error = SnapDiff::Vcs.stub(:checkout_vcs, false) do
      SnapDiff.config.stub(:fail_if_new, true) do
        assert_raises(SnapDiff::ExpectationNotMet) do
          SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
        end
      end
    end

    assert_includes error.message, path.to_s
    assert_no_match(/\.base\.png/, error.message)
    assert_no_match(/RECORD_SCREENSHOTS/, error.message)
    # The canonical name, not the v1 namespace it used to print in the
    # release whose headline is SnapDiff.
    assert_includes error.message, "SnapDiff.config.fail_if_new = false"
  end
end
