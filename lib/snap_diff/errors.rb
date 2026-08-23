# frozen_string_literal: true

require "snap_diff/error_with_filtered_backtrace"

# ADR-008 step 2: the gem's error classes live under SnapDiff. The old
# CapybaraScreenshotDiff names (capybara_screenshot_diff.rb) are EAGER
# same-object aliases of these classes -- deliberately not const_missing
# shims, because rescue clauses and defined?/const_defined? feature
# detection in adopter code must keep behaving exactly as before
# (const_defined? never triggers const_missing).
#
# Error is the catch-all docs/snapdiff.md advertises: EVERY error this gem
# raises inherits it, so `rescue SnapDiff::Error` really does catch them all
# (pinned by test/unit/errors_alias_test.rb, which discovers the classes
# rather than listing them). ErrorWithFilteredBacktrace is plumbing, not a
# second root.
module SnapDiff
  class Error < ErrorWithFilteredBacktrace; end

  class ExpectationNotMet < Error; end

  class UnstableImage < Error; end

  class WindowSizeMismatchError < Error; end
end
