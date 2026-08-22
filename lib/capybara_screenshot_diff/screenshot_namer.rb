# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): CapybaraScreenshotDiff::ScreenshotNamer now
# resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::ScreenshotNamer.
require "snap_diff/screenshot_namer"
require "snap_diff/legacy_shims"
