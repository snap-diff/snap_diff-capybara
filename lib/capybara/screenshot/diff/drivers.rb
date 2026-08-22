# frozen_string_literal: true

require "snap_diff/drivers"

module Capybara
  module Screenshot
    module Diff
      # Same-object forwarder (ADR-004 v2 step 4): aliasing the whole module
      # keeps Drivers.for and the lazily-loaded Drivers::VipsDriver /
      # Drivers::ChunkyPNGDriver constants resolving through the old name.
      Drivers = SnapDiff::Drivers
    end
  end
end
