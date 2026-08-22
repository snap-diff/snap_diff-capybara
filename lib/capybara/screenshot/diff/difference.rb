# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 5): the comparison-result value object lives at
# SnapDiff::ComparisonResult now (ex-Difference).
require "snap_diff/comparison_result"

module Capybara
  module Screenshot
    module Diff
      Difference = SnapDiff::ComparisonResult
    end
  end
end
