# frozen_string_literal: true

require "snap_diff/version"

# Deliberately EAGER and silent (v2 step 6 exception): the gemspec resolves
# Capybara::Screenshot::Diff::VERSION at build time, so a lazy warning shim
# would make every `gem build` warn. See snap_diff/legacy_shims.rb for the
# full exception list.
module Capybara
  module Screenshot
    module Diff
      VERSION = SnapDiff::VERSION
    end
  end
end
