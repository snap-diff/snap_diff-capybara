# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): CapybaraScreenshotDiff::Snap now resolves
# lazily via snap_diff/legacy_shims' const_missing, with a deprecation
# warning pointing at SnapDiff::Snap.
require "snap_diff/snap"
require "snap_diff/legacy_shims"
