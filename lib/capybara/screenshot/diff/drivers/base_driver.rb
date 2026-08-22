# frozen_string_literal: true

# BaseDriver was dissolved into the SnapDiff::Driver mixin (ADR-004 v2
# step 4); since step 6 the old name resolves lazily via
# snap_diff/legacy_shims' const_missing, with a deprecation warning.
# Note it is now a module -- `class MyDriver < BaseDriver` becomes
# `include SnapDiff::Driver`.
require "snap_diff/driver"
require "snap_diff/legacy_shims"
