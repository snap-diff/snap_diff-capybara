# frozen_string_literal: true

# Legacy-name forwarder for SnapDiff::Comparison (ex-ImageCompare). Requiring
# this path must keep providing everything the pre-move image_compare.rb did:
# snap_diff/comparison pulls in the ComparisonResult and Drivers units, and the
# shims keep ::Difference, ::Drivers, ::Comparison (the images struct) and
# LOADED_DRIVERS resolvable.
require "snap_diff/comparison"
require "snap_diff/legacy_shims"

# Deliberately EAGER and silent (v2 step 6 exception): Comparison is a
# documented user-facing struct, so adopters feature-detect it with
# defined?/const_defined? -- neither of which triggers const_missing, so a
# lazy shim reported it permanently absent. See snap_diff/legacy_shims.rb
# for the full exception list.
module Capybara
  module Screenshot
    module Diff
      Comparison = SnapDiff::Comparison::Images
    end
  end
end
