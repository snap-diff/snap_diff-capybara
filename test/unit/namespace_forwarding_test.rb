# frozen_string_literal: true

require "test_helper"

# Every old-namespace constant touched by the ADR-004 v2 file-tree move
# must forward to the exact same object as its SnapDiff:: replacement --
# not a copy, not a lookalike, the same object. If a forwarder ever
# breaks (wrong target, deleted alias, typo), this fails loudly instead
# of surfacing as a mysterious downstream `NameError` or a comparison
# that always returns false.
class NamespaceForwardingTest < ActiveSupport::TestCase
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
    "CapybaraScreenshotDiff::AssertionRegistry" => "SnapDiff::AssertionRegistry"
  }.freeze

  # Explicit requires: a dedicated forwarder-identity test shouldn't rely
  # on incidental transitive loads from other test files (or on rake's
  # file-load order within a single process) to make every one of these
  # 21 constants resolvable. Most of these are already pulled in by
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

  MAPPING.each do |old_name, new_name|
    define_method(:"test_#{old_name}_forwards_to_#{new_name}") do
      old_const = Object.const_get(old_name)
      new_const = Object.const_get(new_name)

      assert_same new_const, old_const,
        "expected #{old_name} to be the exact same object as #{new_name}, " \
        "got #{old_const.inspect} vs #{new_const.inspect}"
    end
  end

  test "MAPPING covers all 21 documented forwarders" do
    assert_equal 21, MAPPING.size
  end
end
