# frozen_string_literal: true

# Legacy-name forwarder for SnapDiff::Comparison (ex-ImageCompare). Requiring
# this path must keep providing everything the pre-move image_compare.rb did:
# snap_diff/comparison pulls in the ComparisonResult and Drivers units, and the
# shims keep ::Difference, ::Drivers, ::Comparison (the images struct) and
# LOADED_DRIVERS resolvable.
require "snap_diff/comparison"
require "snap_diff/legacy_shims"

# Capybara::Screenshot::Diff::Comparison (the images-holder struct) is a
# documented user-facing name that adopters feature-detect with
# defined?/const_defined?, so it is assigned EAGERLY rather than shimmed --
# const_defined? never triggers const_missing. That assignment now lives in
# snap_diff/legacy_shims (required above), with the rest of the v1 surface,
# so `require "snap_diff"` alone provides it too.
