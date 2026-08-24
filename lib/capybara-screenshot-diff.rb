# frozen_string_literal: true

# Bundler.require entry point for `gem "capybara-screenshot-diff"` -- the v1
# gem name, deleted in 3.0. The surviving name owns the logic (including the
# minitest feature detection this door needs just as much).
#
# The marker goes BEFORE that require: snap_diff-capybara claims the process
# as canonical, and a marker after it would be swallowed.
require "snap_diff/deprecation"
SnapDiff::Deprecation.legacy_entry_point!

require "snap_diff-capybara"
