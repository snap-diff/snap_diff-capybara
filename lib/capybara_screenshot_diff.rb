# frozen_string_literal: true

# The v1 umbrella, and the file every legacy entry point except
# capybara_screenshot_diff/dsl reaches. Marked here rather than in each of
# them; snap_diff-capybara.rb (which loads this umbrella for canonical
# users) claims the process first, so this stays quiet for them.
require "snap_diff/deprecation"
SnapDiff::Deprecation.legacy_entry_point!

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

# RED_RGBA / ORANGE_RGBA moved to SnapDiff (snap_diff/annotation_service) so
# the bare "snap_diff" entry gets them too; the old names resolve via
# snap_diff/legacy_shims with a deprecation warning.
#
# The four error classes (CapybaraScreenshotDiffError, ExpectationNotMet,
# UnstableImage, WindowSizeMismatchError) used to be assigned here as EAGER
# same-object aliases. They still are eager -- just from
# snap_diff/legacy_shims, so a canonical-only require gets them too.
require "snap_diff/legacy_shims"

require "capybara_screenshot_diff/dsl"

# Eager, not autoload: several lib/snap_diff/* units above (Os,
# Screenshoter, ...) reopen `module SnapDiff` while loading, which cancels
# any registered `autoload :SnapDiff` before it ever fires (Ruby resolves
# the constant the first time anything reopens it, autoload or not) --
# so SnapDiff.start/.compare/.config would silently never be defined
# without this. Safe eagerly: snap_diff.rb never requires this file back.
require "snap_diff"
