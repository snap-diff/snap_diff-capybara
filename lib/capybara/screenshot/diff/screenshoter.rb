# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): Capybara::Screenshot::Screenshoter now
# resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::Screenshoter.
require "snap_diff/screenshoter"
require "snap_diff/legacy_shims"
