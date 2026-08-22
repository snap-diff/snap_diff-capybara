# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): Capybara::Screenshot::Diff::AreaCalculator
# now resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::AreaCalculator.
require "snap_diff/area_calculator"
require "snap_diff/legacy_shims"
