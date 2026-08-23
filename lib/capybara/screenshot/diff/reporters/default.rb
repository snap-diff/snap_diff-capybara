# frozen_string_literal: true

# Legacy-name forwarder for SnapDiff::Reporters::Default.
# `Capybara::Screenshot::Diff::Reporters::Default` is an EAGER same-object
# alias assigned in snap_diff/legacy_shims -- the one file every entry point
# loads, canonical ones included, so a half-migrated app keeps the name.
require "snap_diff/reporters/default"
require "snap_diff/legacy_shims"
