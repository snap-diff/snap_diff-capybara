# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): the comparison-result value object lives at
# SnapDiff::ComparisonResult (ex-Difference); the old name now resolves
# lazily via snap_diff/legacy_shims' const_missing, with a deprecation
# warning.
require "snap_diff/comparison_result"
require "snap_diff/legacy_shims"
