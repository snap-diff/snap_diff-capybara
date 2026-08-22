# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): Capybara::Screenshot::Diff::Drivers now
# resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::Drivers. The forwarded module is
# the same object, so Drivers.for and the Drivers::VipsDriver /
# Drivers::ChunkyPNGDriver constants keep resolving through the old name.
require "snap_diff/drivers"
require "snap_diff/legacy_shims"
