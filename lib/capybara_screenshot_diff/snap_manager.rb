# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): CapybaraScreenshotDiff::SnapManager now
# resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::SnapManager.
require "snap_diff/snap_manager"
require "snap_diff/legacy_shims"
