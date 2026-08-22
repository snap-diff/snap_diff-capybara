# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 6): Capybara::Screenshot::Diff::ImagePreprocessor
# now resolves lazily via snap_diff/legacy_shims' const_missing, with a
# deprecation warning pointing at SnapDiff::ImagePreprocessor.
require "snap_diff/image_preprocessor"
require "snap_diff/legacy_shims"
