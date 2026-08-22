# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): Capybara::Screenshot::Diff::StableScreenshoter
# now resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::StableScreenshoter.
require "snap_diff/stable_screenshoter"
require "snap_diff/legacy_shims"
