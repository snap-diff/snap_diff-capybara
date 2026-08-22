# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): Capybara::Screenshot::Diff::Vcs now
# resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::Vcs.
require "snap_diff/vcs"
require "snap_diff/legacy_shims"
