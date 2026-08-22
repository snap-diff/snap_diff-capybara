# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): CapybaraScreenshotDiff::AttemptsReporter now
# resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::AttemptsReporter.
require "snap_diff/attempts_reporter"
require "snap_diff/legacy_shims"
