# frozen_string_literal: true

require "snap_diff/error_with_filtered_backtrace"

# ADR-008 step 2: the gem's error classes live under SnapDiff. 2.1 deleted
# the v1 aliases of them, so these names are the only ones.
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
