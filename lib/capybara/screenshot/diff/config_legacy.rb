# frozen_string_literal: true

# Legacy Capybara::Screenshot / Capybara::Screenshot::Diff config surface.
#
# Since ADR-008 step 1 the storage lives in SnapDiff::Config -- the require
# leaf of the config graph (see its own header) -- and this file installs
# the old accessor names as thin delegators onto SnapDiff.config, generated
# from SnapDiff::Config::MAPPING. The v1 write surface
# (Capybara::Screenshot.window_size = ..., Diff.configure { ... }) keeps
# working unchanged: one storage, two views.
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
        enabled || (enabled.nil? && Diff.enabled)
      end

      def screenshot_area
        parts = [Screenshot.save_path]
        parts << SnapDiff::Os.name if Screenshot.add_os_path
        parts << Capybara.current_driver.to_s if Screenshot.add_driver_path
        File.join(*parts)
      end

      def screenshot_area_abs
        root / screenshot_area
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
      def self.configure
        yield Screenshot, self
      end

      def self.compare(baseline_path, current_path, **options)
        SnapDiff::Comparison.new(current_path, baseline_path, default_options.merge(options))
      end

      def self.default_options
        {
          area_size_limit: area_size_limit,
          color_distance_limit: color_distance_limit,
          driver: driver,
          screenshot_format: Screenshot.screenshot_format,
          capybara_screenshot_options: Screenshot.capybara_screenshot_options,
          perceptual_threshold: perceptual_threshold,
          shift_distance_limit: shift_distance_limit,
          skip_area: skip_area,
          stability_time_limit: Screenshot.stability_time_limit,
          tolerance: tolerance || ((driver == :vips) ? 0.001 : nil),
          # Deliberately LIVE (pinned by config_default_timing_test.rb):
          # read at call time, never frozen into storage.
          wait: Capybara.default_max_wait_time
        }
      end
    end

    # The old mattr_accessor surface, now delegating to the single storage.
    # mattr_accessor used to define both singleton and instance accessors
    # (the instance ones are what `include Capybara::Screenshot::Diff`
    # picks up), so both are installed. root keeps its historical
    # asymmetry -- readable everywhere, writable only at module level
    # (it was mattr_reader plus a custom module-level writer) -- with the
    # Pathname coercion now living in Config#root=.
    SnapDiff::Config::MAPPING.each do |name, (mod, mattr)|
      [mod, mod.singleton_class].each do |target|
        target.define_method(mattr) { SnapDiff.config.public_send(name) }
        next if name == :root && target == mod

        target.define_method(:"#{mattr}=") { |value| SnapDiff.config.public_send(:"#{name}=", value) }
      end
    end
  end
end
