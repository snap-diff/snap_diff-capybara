# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): Capybara::Screenshot::Diff::ScreenshotMatcher
# now resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::ScreenshotMatcher.
require "snap_diff/screenshot_matcher"
require "snap_diff/legacy_shims"
