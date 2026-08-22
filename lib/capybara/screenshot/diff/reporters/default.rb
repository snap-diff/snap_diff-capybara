# frozen_string_literal: true

# Forwarder (ADR-008 step 4): the default reporter lives at
# SnapDiff::Reporters::Default; the old name now resolves lazily via
# snap_diff/legacy_shims' const_missing, with a deprecation warning.
require "snap_diff/reporters/default"
require "snap_diff/legacy_shims"
