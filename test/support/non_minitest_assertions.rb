# frozen_string_literal: true

require "snap_diff/dsl"

# Stands in for a non-minitest adapter: the raw session lifecycle a host
# framework's integration has to drive itself.
module NonMinitest
  module Assertions
    def self.included(klass)
      klass.include SnapDiff::DSL

      klass.setup do
        SnapDiff::BrowserHelpers.resize_window_if_needed
      end

      klass.teardown do
        SnapDiff.session.verify
      ensure
        SnapDiff.reset
      end
    end
  end
end
