# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): the comparison class lives at
# SnapDiff::Comparison (ex-ImageCompare); the old name now resolves lazily
# via snap_diff/legacy_shims' const_missing, with a deprecation warning.
# snap_diff/comparison itself pulls in the ComparisonResult and Drivers
# units, and the shims keep the old ::Difference / ::Drivers names
# resolvable, so this path still provides everything the pre-move
# image_compare.rb did. The internal images-holder struct lives at
# SnapDiff::Comparison::Images (its old ::Comparison name resolves via the
# shims) and the driver cache at SnapDiff::Drivers.loaded, with
# LOADED_DRIVERS kept as an eager same-object alias by legacy_shims
# (ADR-008 step 5).
require "snap_diff/comparison"
require "snap_diff/legacy_shims"
