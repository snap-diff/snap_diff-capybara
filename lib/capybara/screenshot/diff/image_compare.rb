# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 5): the comparison class lives at
# SnapDiff::Comparison now (ex-ImageCompare). The old drivers/difference
# requires keep this path providing the Capybara::Screenshot::Diff::Drivers
# and ::Difference aliases, exactly as the pre-move image_compare.rb did via
# its own requires. The internal Comparison struct and LOADED_DRIVERS keep
# their legacy names and are defined by snap_diff/comparison.rb itself.
require "capybara/screenshot/diff/drivers"
require "capybara/screenshot/diff/difference"
require "snap_diff/comparison"

module Capybara
  module Screenshot
    module Diff
      ImageCompare = SnapDiff::Comparison
    end
  end
end
