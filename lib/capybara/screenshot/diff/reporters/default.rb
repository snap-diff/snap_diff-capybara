# frozen_string_literal: true

# Forwarder (ADR-008 step 4): the default reporter lives at
# SnapDiff::Reporters::Default.
require "snap_diff/reporters/default"
require "snap_diff/legacy_shims"

# Deliberately EAGER and silent (v2 step 6 exception): Default is a
# documented subclassing extension point, so adopters feature-detect it with
# defined?/const_defined? -- neither of which triggers const_missing, so a
# lazy shim reported it permanently absent. See snap_diff/legacy_shims.rb
# for the full exception list.
module Capybara
  module Screenshot
    module Diff
      module Reporters
        Default = SnapDiff::Reporters::Default
      end
    end
  end
end
