# frozen_string_literal: true

# Legacy Capybara::Screenshot / Capybara::Screenshot::Diff mattr_accessor
# config module, extracted out of capybara_screenshot_diff.rb so it is a
# leaf: it can be required by both capybara_screenshot_diff.rb (the old
# umbrella entry point) and snap_diff.rb (the canonical entry point)
# without either of *those* requiring the other back.
#
# Why this file has to exist at all: several lib/snap_diff/* units
# (Screenshoter, SnapManager, Utils) are referenced here at class-body
# eval time (mattr_accessor default blocks, AVAILABLE_DRIVERS) rather
# than at call time, so they must be real, already-loaded classes before
# this module body runs. Since v2 step 6 they are pulled in and referenced
# under their canonical SnapDiff names: the old-name aliases are lazy
# const_missing shims that emit deprecation warnings, and the gem's own
# code must stay warning-free. Everything else this module references
# (Os, Comparison) is referenced only inside method bodies, resolved
# lazily at call time by whichever entry point loaded them.
require "snap_diff/screenshoter"
require "snap_diff/snap_manager"
require "snap_diff/utils"

module Capybara
  module Screenshot
    mattr_accessor :add_driver_path
    mattr_accessor :add_os_path
    mattr_accessor(:blur_active_element) { true }
    mattr_accessor :enabled
    mattr_accessor(:hide_caret) { true }
    mattr_accessor :disable_animations
    mattr_reader(:root) { (defined?(Rails) && defined?(Rails.root) && Rails.root) || Pathname(".").expand_path }
    mattr_accessor :stability_time_limit
    mattr_accessor :window_size
    mattr_accessor(:save_path) { "doc/screenshots" }
    mattr_accessor(:use_lfs)
    mattr_accessor(:screenshot_format) { "png" }
    mattr_accessor(:capybara_screenshot_options) { {} }

    class << self
      def root=(path)
        @@root = Pathname(path).expand_path
      end

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
      mattr_accessor(:delayed) { true }
      mattr_accessor :area_size_limit
      mattr_accessor(:fail_if_new) { !ENV["CI"].nil? && !ENV["CI"].empty? }
      mattr_accessor(:pending_if_new) { false }
      mattr_accessor(:fail_on_difference) { true }
      mattr_accessor :color_distance_limit
      mattr_accessor(:enabled) { true }
      mattr_accessor :shift_distance_limit
      mattr_accessor :skip_area
      mattr_accessor(:driver) { :auto }
      mattr_accessor :tolerance
      mattr_accessor :perceptual_threshold

      mattr_accessor(:screenshoter) { SnapDiff::Screenshoter }
      mattr_accessor(:manager) { SnapDiff::SnapManager }

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
          wait: Capybara.default_max_wait_time
        }
      end
    end
  end
end
