# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): CapybaraScreenshotDiff::Reporters::HTML now
# resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::Reporters::HTML.
require "snap_diff/reporters/html"
require "snap_diff/legacy_shims"
