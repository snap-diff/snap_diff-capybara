# frozen_string_literal: true

# Forwarder (ADR-008 step 3): Region now lives at SnapDiff::Region;
# snap_diff/region also defines the eager top-level `Region` alias.
require "snap_diff/region"
