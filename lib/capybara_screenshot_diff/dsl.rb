# frozen_string_literal: true

require "snap_diff/dsl"

# Deliberately EAGER and silent (v2 step 6 exception): DSL is an advertised
# entry-point constant probed with Object.const_defined? by
# support_load_probe_test.rb, and const_defined? never triggers
# const_missing -- a lazy shim would break that contract. See
# snap_diff/legacy_shims.rb for the full exception list.
module CapybaraScreenshotDiff
  DSL = SnapDiff::DSL
end
