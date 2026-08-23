# frozen_string_literal: true

# Legacy-name forwarder. `Capybara::Screenshot::Os` is an EAGER same-object
# alias assigned in snap_diff/legacy_shims -- the one file every entry point
# loads, canonical ones included, so a half-migrated app keeps the name.
require "snap_diff/os"
require "snap_diff/legacy_shims"
