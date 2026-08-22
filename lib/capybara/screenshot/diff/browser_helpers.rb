# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): Capybara::Screenshot::BrowserHelpers now
# resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::BrowserHelpers.
require "snap_diff/browser_helpers"
require "snap_diff/legacy_shims"
