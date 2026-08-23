# frozen_string_literal: true

require "snap_diff/version"

# Deliberately EAGER and silent (v2 step 6 exception): this is a documented
# name that adopters read directly, and const_defined? never triggers
# const_missing. The gemspec used to resolve it at build time (which a lazy
# warning shim would have made warn on every `gem build`); it reads
# SnapDiff::VERSION now, so this file is pure compatibility. See
# snap_diff/legacy_shims.rb for the full exception list.
module Capybara
  module Screenshot
    module Diff
      VERSION = SnapDiff::VERSION
    end
  end
end
