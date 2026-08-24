# frozen_string_literal: true

# v1 require path, kept as a one-line alias entry (ADR-008 amendment): four
# of six discoverable real users import this gem under its v1 names, and a
# LoadError here fires before any constant alias could help them.
#
# It loads the minitest integration for the same reason the gem-name entries
# do -- that is what the v1 entry point always activated.
require "snap_diff/integrations/minitest"
