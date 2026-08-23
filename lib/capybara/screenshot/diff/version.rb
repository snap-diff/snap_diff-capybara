# frozen_string_literal: true

# Capybara::Screenshot::Diff::VERSION is a documented name adopters read
# directly, so it is assigned EAGERLY rather than shimmed -- const_defined?
# never triggers const_missing. That assignment lives in
# snap_diff/legacy_shims (required below) with the rest of the v1 surface,
# because this file is no longer on any entry point's require path: the core
# reads SnapDiff::VERSION, and so does the gemspec. Assigning it here too
# would be a duplicate-constant warning, not a second safety net.
require "snap_diff/legacy_shims"
