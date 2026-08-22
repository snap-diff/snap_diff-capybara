# frozen_string_literal: true

# Legacy Capybara::Screenshot / Capybara::Screenshot::Diff config surface.
#
# Since ADR-008 step 1 the storage lives in SnapDiff::Config -- the require
# leaf of the config graph (see its own header) -- and since step 7b the
# DERIVED values (active?, screenshot_area, default_options) live there
# too. snap_diff/config.rb also generates the old accessor names as thin
# delegators from SnapDiff::Config::MAPPING, so nothing but forwarders is
# left here. The v1 surface (Capybara::Screenshot.window_size = ...,
# Diff.configure { ... }, Diff.compare) keeps working unchanged: one
# storage, two views.
#
# Load order: requiring snap_diff/config first also eagerly evaluates the
# require-time defaults (ENV["CI"] for fail_if_new, Rails.root/pwd for
# root) at this same load moment, exactly when the old mattr_accessor
# default blocks used to run. snap_diff/config never requires back here,
# so the graph stays acyclic.
require "snap_diff/config"
# AVAILABLE_DRIVERS below is evaluated at class-body eval time, so Utils
# must be a real, already-loaded module before this module body runs.
require "snap_diff/utils"

module Capybara
  module Screenshot
    class << self
      def active?
        SnapDiff.config.active?
      end

      def screenshot_area
        SnapDiff.config.screenshot_area
      end

      def screenshot_area_abs
        SnapDiff.config.screenshot_area_abs
      end
    end

    # Module to track screenshot changes
    module Diff
      AVAILABLE_DRIVERS = SnapDiff::Utils.detect_available_drivers.freeze

      # Configure screenshot and diff settings in one block.
      #
      #   Capybara::Screenshot::Diff.configure do |screenshot, diff|
      #     screenshot.window_size = [1280, 1024]
      #     screenshot.stability_time_limit = 1
      #     diff.driver = :vips
      #     diff.tolerance = 0.0005
      #   end
      # The bare `yield` (rather than an explicit &block) keeps this
      # method's published arity byte-identical to what it always had.
      def self.configure
        SnapDiff.start { |screenshot, diff| yield screenshot, diff }
      end

      def self.compare(baseline_path, current_path, **options)
        SnapDiff.compare(baseline_path, current_path, **options)
      end

      def self.default_options
        SnapDiff.config.default_options
      end
    end
  end
end
