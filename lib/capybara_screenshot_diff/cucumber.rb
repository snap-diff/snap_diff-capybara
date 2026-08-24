# frozen_string_literal: true

# v1 require path, kept as a one-line alias entry (ADR-008 amendment).
# No discoverable user, but its two siblings are kept: an entry point that
# LoadErrors while the other two work is a worse surface than either choice.
require "snap_diff/integrations/cucumber"
