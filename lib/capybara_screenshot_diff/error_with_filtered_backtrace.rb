# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): CapybaraScreenshotDiff::BacktraceFilter and
# CapybaraScreenshotDiff::ErrorWithFilteredBacktrace now resolve lazily via
# snap_diff/legacy_shims' const_missing, with deprecation warnings pointing
# at their SnapDiff:: replacements.
require "snap_diff/error_with_filtered_backtrace"
require "snap_diff/legacy_shims"
