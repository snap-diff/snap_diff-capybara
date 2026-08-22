# frozen_string_literal: true

require "capybara/dsl"
require "capybara/screenshot/diff/config_legacy"
require "capybara/screenshot/diff/version"
require "capybara/screenshot/diff/os"
require "capybara/screenshot/diff/browser_helpers"
require "capybara/screenshot/diff/utils"
require "capybara/screenshot/diff/image_compare"
require "capybara_screenshot_diff/snap_manager"
require "capybara_screenshot_diff/snap"
require "capybara/screenshot/diff/screenshoter"
require "capybara/screenshot/diff/stable_screenshoter"
require "capybara/screenshot/diff/vcs"
require "capybara/screenshot/diff/area_calculator"
require "capybara/screenshot/diff/image_preprocessor"
require "capybara/screenshot/diff/annotation_service"
require "capybara_screenshot_diff/screenshot_namer"
require "capybara_screenshot_diff/screenshot_assertion"
require "capybara_screenshot_diff/attempts_reporter"
require "capybara/screenshot/diff/screenshot_matcher"
require "capybara/screenshot/diff/reporters/default"

require "capybara_screenshot_diff/error_with_filtered_backtrace"

module CapybaraScreenshotDiff
  RED_RGBA = [255, 0, 0, 255].freeze
  ORANGE_RGBA = [255, 192, 0, 255].freeze

  class CapybaraScreenshotDiffError < SnapDiff::ErrorWithFilteredBacktrace; end

  class ExpectationNotMet < CapybaraScreenshotDiffError; end

  class UnstableImage < CapybaraScreenshotDiffError; end

  class WindowSizeMismatchError < SnapDiff::ErrorWithFilteredBacktrace; end
end

require "capybara_screenshot_diff/dsl"

# Eager, not autoload: several lib/snap_diff/* units above (Os,
# Screenshoter, ...) reopen `module SnapDiff` while loading, which cancels
# any registered `autoload :SnapDiff` before it ever fires (Ruby resolves
# the constant the first time anything reopens it, autoload or not) --
# so SnapDiff.start/.compare/.config would silently never be defined
# without this. Safe to do eagerly, unlike before this file's units
# moved: snap_diff.rb no longer requires this file back (it only needs
# the leaf config_legacy.rb + image_compare.rb), so there is no cycle.
require "snap_diff"
