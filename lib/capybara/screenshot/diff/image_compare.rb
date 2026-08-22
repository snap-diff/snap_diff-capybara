# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): the comparison class lives at
# SnapDiff::Comparison (ex-ImageCompare); the old name now resolves lazily
# via snap_diff/legacy_shims' const_missing, with a deprecation warning.
# snap_diff/comparison itself pulls in the ComparisonResult and Drivers
# units, and the shims keep the old ::Difference / ::Drivers names
# resolvable, so this path still provides everything the pre-move
# image_compare.rb did. The internal Comparison struct and LOADED_DRIVERS
# keep their legacy names and are defined by snap_diff/comparison.rb itself.
require "snap_diff/comparison"
require "snap_diff/legacy_shims"
