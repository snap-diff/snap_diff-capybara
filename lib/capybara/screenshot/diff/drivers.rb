# frozen_string_literal: true

# Legacy-name forwarder: the old constant resolves via snap_diff/legacy_shims.
# The forwarded module is the same object, so Drivers.for and the
# Drivers::VipsDriver / Drivers::ChunkyPNGDriver constants keep resolving
# through the old name.
require "snap_diff/drivers"
require "snap_diff/legacy_shims"
