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
require "snap_diff/errors"

module CapybaraScreenshotDiff
  # RED_RGBA / ORANGE_RGBA moved to SnapDiff (snap_diff/annotation_service)
  # so the bare "snap_diff" entry gets them too; the old names resolve via
  # snap_diff/legacy_shims with a deprecation warning.

  # The error classes live in SnapDiff (snap_diff/errors). These are EAGER
  # same-object aliases -- deliberately not const_missing
  # shims -- so rescue-by-old-name and defined?/const_defined? feature
  # detection keep working exactly as before (const_defined? never
  # triggers const_missing).
  CapybaraScreenshotDiffError = SnapDiff::Error

  ExpectationNotMet = SnapDiff::ExpectationNotMet

  UnstableImage = SnapDiff::UnstableImage

  WindowSizeMismatchError = SnapDiff::WindowSizeMismatchError
end

require "capybara_screenshot_diff/dsl"

# Eager, not autoload: several lib/snap_diff/* units above (Os,
# Screenshoter, ...) reopen `module SnapDiff` while loading, which cancels
# any registered `autoload :SnapDiff` before it ever fires (Ruby resolves
# the constant the first time anything reopens it, autoload or not) --
# so SnapDiff.start/.compare/.config would silently never be defined
# without this. Safe eagerly: snap_diff.rb never requires this file back.
require "snap_diff"
