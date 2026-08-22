# frozen_string_literal: true

require "snap_diff/error_with_filtered_backtrace"

module CapybaraScreenshotDiff
  BacktraceFilter = SnapDiff::BacktraceFilter
  ErrorWithFilteredBacktrace = SnapDiff::ErrorWithFilteredBacktrace
end
