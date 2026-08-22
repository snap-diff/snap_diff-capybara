# frozen_string_literal: true

require "test_helper"

# Every old-namespace constant touched by the ADR-004 v2 file-tree move
# must forward to the exact same object as its SnapDiff:: replacement --
# not a copy, not a lookalike, the same object. If a forwarder ever
# breaks (wrong target, deleted alias, typo), this fails loudly instead
# of surfacing as a mysterious downstream `NameError` or a comparison
# that always returns false.
class NamespaceForwardingTest < ActiveSupport::TestCase
  # This file's whole purpose is resolving the old names, so silence the
  # shims' deprecation warnings here (the suite-wide guard in test_helper
  # raises on any unexpected one); the warning behavior itself is pinned by
  # legacy_namespace_deprecation_test.rb.
  setup do
    @original_silence = SnapDiff.silence_deprecations
    SnapDiff.silence_deprecations = true
  end

  teardown do
    SnapDiff.silence_deprecations = @original_silence
  end

  # old constant path => new constant path
  MAPPING = {
    "Capybara::Screenshot::Os" => "SnapDiff::Os",
    "Capybara::Screenshot::BrowserHelpers" => "SnapDiff::BrowserHelpers",
    "Capybara::Screenshot::Diff::Vcs" => "SnapDiff::Vcs",
    "Capybara::Screenshot::Diff::VERSION" => "SnapDiff::VERSION",
    "Capybara::Screenshot::Screenshoter" => "SnapDiff::Screenshoter",
    "Capybara::Screenshot::Diff::StableScreenshoter" => "SnapDiff::StableScreenshoter",
    "Capybara::Screenshot::Diff::ImagePreprocessor" => "SnapDiff::ImagePreprocessor",
    "Capybara::Screenshot::Diff::AreaCalculator" => "SnapDiff::AreaCalculator",
    "Capybara::Screenshot::Diff::AnnotationService" => "SnapDiff::AnnotationService",
    "Capybara::Screenshot::Diff::Utils" => "SnapDiff::Utils",
    "Capybara::Screenshot::Diff::ScreenshotMatcher" => "SnapDiff::ScreenshotMatcher",
    "CapybaraScreenshotDiff::DSL" => "SnapDiff::DSL",
    "CapybaraScreenshotDiff::SnapManager" => "SnapDiff::SnapManager",
    "CapybaraScreenshotDiff::Snap" => "SnapDiff::Snap",
    "CapybaraScreenshotDiff::ScreenshotNamer" => "SnapDiff::ScreenshotNamer",
    "CapybaraScreenshotDiff::AttemptsReporter" => "SnapDiff::AttemptsReporter",
    "CapybaraScreenshotDiff::BacktraceFilter" => "SnapDiff::BacktraceFilter",
    "CapybaraScreenshotDiff::ErrorWithFilteredBacktrace" => "SnapDiff::ErrorWithFilteredBacktrace",
    "CapybaraScreenshotDiff::Reporters::HTML" => "SnapDiff::Reporters::HTML",
    "CapybaraScreenshotDiff::ScreenshotAssertion" => "SnapDiff::ScreenshotAssertion",
    "CapybaraScreenshotDiff::AssertionRegistry" => "SnapDiff::AssertionRegistry",
    "Capybara::Screenshot::Diff::Drivers" => "SnapDiff::Drivers",
    "Capybara::Screenshot::Diff::Drivers::BaseDriver" => "SnapDiff::Driver",
    "Capybara::Screenshot::Diff::Drivers::ChunkyPNGDriver" => "SnapDiff::Drivers::ChunkyPNGDriver",
    "Capybara::Screenshot::Diff::Drivers::VipsDriver" => "SnapDiff::Drivers::VipsDriver",
    "Capybara::Screenshot::Diff::Reporters::Default" => "SnapDiff::Reporters::Default",
    "Capybara::Screenshot::Diff::ImageCompare" => "SnapDiff::Comparison",
    "Capybara::Screenshot::Diff::Comparison" => "SnapDiff::Comparison::Images",
    "Capybara::Screenshot::Diff::Difference" => "SnapDiff::ComparisonResult",
    "CapybaraScreenshotDiff::RED_RGBA" => "SnapDiff::RED_RGBA",
    "CapybaraScreenshotDiff::ORANGE_RGBA" => "SnapDiff::ORANGE_RGBA"
  }.freeze

  # Explicit requires: a dedicated forwarder-identity test shouldn't rely
  # on incidental transitive loads from other test files (or on rake's
  # file-load order within a single process) to make every one of these
  # constants resolvable. Most of these are already pulled in by
  # test_helper's own "capybara_screenshot_diff/minitest" require; listed
  # here anyway so this file passes standalone.
  require "capybara/screenshot/diff/os"
  require "capybara/screenshot/diff/browser_helpers"
  require "capybara/screenshot/diff/vcs"
  require "capybara/screenshot/diff/version"
  require "capybara/screenshot/diff/screenshoter"
  require "capybara/screenshot/diff/stable_screenshoter"
  require "capybara/screenshot/diff/image_preprocessor"
  require "capybara/screenshot/diff/area_calculator"
  require "capybara/screenshot/diff/annotation_service"
  require "capybara/screenshot/diff/utils"
  require "capybara/screenshot/diff/screenshot_matcher"
  require "capybara_screenshot_diff/dsl"
  require "capybara_screenshot_diff/snap_manager"
  require "capybara_screenshot_diff/snap"
  require "capybara_screenshot_diff/screenshot_namer"
  require "capybara_screenshot_diff/attempts_reporter"
  require "capybara_screenshot_diff/error_with_filtered_backtrace"
  require "capybara_screenshot_diff/reporters/html"
  require "capybara_screenshot_diff/screenshot_assertion"
  require "capybara/screenshot/diff/reporters/default"
  require "capybara/screenshot/diff/drivers"
  require "capybara/screenshot/diff/drivers/base_driver"
  require "capybara/screenshot/diff/drivers/chunky_png_driver"
  require "capybara/screenshot/diff/image_compare"
  require "capybara/screenshot/diff/difference"
  begin
    require "capybara/screenshot/diff/drivers/vips_driver"
  rescue LoadError, RuntimeError # vips_driver.rb re-raises missing-gem LoadError as RuntimeError
    # vips-less runner: the VipsDriver pair reports as a skip below,
    # mirroring test/unit/drivers/vips_driver_test.rb.
  end

  MAPPING.each do |old_name, new_name|
    define_method(:"test_#{old_name}_forwards_to_#{new_name}") do
      skip "vips not available on this runner" if new_name.include?("Vips") && !defined?(SnapDiff::Drivers::VipsDriver)

      old_const = Object.const_get(old_name)
      new_const = Object.const_get(new_name)

      assert_same new_const, old_const,
        "expected #{old_name} to be the exact same object as #{new_name}, " \
        "got #{old_const.inspect} vs #{new_const.inspect}"
    end
  end

  test "MAPPING covers all 31 documented forwarders" do
    assert_equal 31, MAPPING.size
  end

  # Driver registries (ADR-008 step 5b): not part of MAPPING because the
  # old names are EAGER aliases (never warn) of the canonical
  # SnapDiff::Drivers accessors -- LOADED_DRIVERS is mutated in place by
  # user driver registration, so it must stay the exact same object.
  test "driver registries are the same object under old and canonical names" do
    assert_same SnapDiff::Drivers.loaded, Capybara::Screenshot::Diff::LOADED_DRIVERS
    assert_same SnapDiff::Drivers.available, Capybara::Screenshot::Diff::AVAILABLE_DRIVERS
  end

  test "driver registration through the legacy LOADED_DRIVERS constant is visible canonically" do
    Capybara::Screenshot::Diff::LOADED_DRIVERS[:forwarding_probe] = :probe_driver

    assert_equal :probe_driver, SnapDiff::Drivers.loaded[:forwarding_probe]
  ensure
    SnapDiff::Drivers.loaded.delete(:forwarding_probe)
  end
end
