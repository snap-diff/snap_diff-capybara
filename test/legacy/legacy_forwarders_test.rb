# frozen_string_literal: true

require "test_helper"
# The shared harness loads canonical entry points only, so a legacy-surface
# test pulls in the v1 entry itself -- the require goes with the file in 3.0.
require "capybara_screenshot_diff"
require "capybara_screenshot_diff/static"

# LEGACY SURFACE (test/legacy/, see the Rakefile).
#
# The identity claims that make the old CapybaraScreenshotDiff module a
# *view* of the canonical state rather than a second copy of it, plus the
# v1-shaped SnapDiff.start. Collected here from the canonical tests they
# used to sit in (registry_concurrency_test, reporters_mutex_test,
# snap_diff_test): a mechanical repoint would have turned each of them into
# `assert_same X, X`, which is how a real claim quietly becomes a tautology.
# Verbatim, so the v1 contract keeps exactly the coverage it had.
class LegacyForwardersTest < ActiveSupport::TestCase
  setup do
    # These resolve old-namespace names on purpose; the suite-wide guard in
    # test_helper raises on unexpected shim warnings.
    @original_silence = SnapDiff.silence_deprecations
    SnapDiff.silence_deprecations = true
  end

  teardown do
    SnapDiff.silence_deprecations = @original_silence
  end

  # ADR-008 step 6: SnapDiff.session is the canonical accessor and
  # CapybaraScreenshotDiff.registry a forwarder over it -- they must hand
  # back the *same* object, not two registries that happen to look alike.
  test "SnapDiff.session and CapybaraScreenshotDiff.registry are the same object" do
    assert_same SnapDiff.session, CapybaraScreenshotDiff.registry

    SnapDiff.session.record_new_screenshot("shared_object_probe")
    assert_equal ["shared_object_probe"], CapybaraScreenshotDiff.new_screenshots
  ensure
    SnapDiff.session.reset
  end

  # ADR-008 step 6: SnapDiff::Reporting.register is the canonical way in;
  # CapybaraScreenshotDiff.reporters stays as the compat view of the same
  # array, so a registration must be visible through both.
  test "register appends to the array CapybaraScreenshotDiff.reporters exposes" do
    original_reporters = CapybaraScreenshotDiff.reporters.dup
    CapybaraScreenshotDiff.reporters.clear
    reporter = Object.new

    assert_same reporter, SnapDiff::Reporting.register(reporter)
    assert_same SnapDiff::Reporting.reporters, CapybaraScreenshotDiff.reporters
    assert_includes CapybaraScreenshotDiff.reporters, reporter
  ensure
    CapybaraScreenshotDiff.reporters.clear
    CapybaraScreenshotDiff.reporters.concat(original_reporters)
  end

  test "CapybaraScreenshotDiff.reporters_mutex is the canonical Reporting mutex" do
    assert_same SnapDiff::Reporting.mutex, CapybaraScreenshotDiff.reporters_mutex
  end

  test "Capybara::Screenshot::Diff::ImageCompare aliases SnapDiff::Comparison" do
    assert_same SnapDiff::Comparison, Capybara::Screenshot::Diff::ImageCompare
  end

  test "CapybaraScreenshotDiff.serve forwards to SnapDiff.serve, custom root included" do
    original_root = SnapDiff.config.root

    CapybaraScreenshotDiff.serve("test/fixtures", root: "/tmp")

    assert_equal Pathname("/tmp"), SnapDiff.config.root
  ensure
    Capybara.app = Rails.application
    SnapDiff.config.root = original_root
  end

  test ".start yields the same objects Diff.configure yields" do
    yielded = []
    Capybara::Screenshot::Diff.configure { |screenshot, diff| yielded << [screenshot, diff] }

    started = []
    SnapDiff.start { |screenshot, diff| started << [screenshot, diff] }

    assert_equal yielded, started
  end

  test ".start applies a setting like Diff.configure does" do
    original = SnapDiff.config.tolerance

    begin
      SnapDiff.start { |_screenshot, diff| diff.tolerance = 0.0123 }

      assert_equal 0.0123, SnapDiff.config.tolerance
    ensure
      SnapDiff.config.tolerance = original
    end
  end
end
