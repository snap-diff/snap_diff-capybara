# frozen_string_literal: true

require "capybara/dsl"
require "capybara/screenshot/diff/version"
require "capybara/screenshot/diff/utils"
require "capybara/screenshot/diff/image_compare"
require "capybara_screenshot_diff/snap_manager"
require "capybara/screenshot/diff/screenshoter"
require "capybara/screenshot/diff/reporters/default"

require "capybara_screenshot_diff/error_with_filtered_backtrace"

module CapybaraScreenshotDiff
  RED_RGBA = [255, 0, 0, 255].freeze
  ORANGE_RGBA = [255, 192, 0, 255].freeze

  class CapybaraScreenshotDiffError < ErrorWithFilteredBacktrace; end

  class ExpectationNotMet < CapybaraScreenshotDiffError; end

  class UnstableImage < CapybaraScreenshotDiffError; end

  class WindowSizeMismatchError < ErrorWithFilteredBacktrace; end
end

module Capybara
  module Screenshot
    mattr_accessor :add_driver_path
    mattr_accessor :add_os_path
    mattr_accessor(:blur_active_element) { true }
    mattr_accessor :enabled
    mattr_accessor(:hide_caret) { true }
    mattr_accessor :disable_animations
    mattr_accessor(:normalize_css) { true }
    mattr_accessor :normalize_stylesheet
    mattr_accessor(:wait_for_fonts) { true }
    mattr_accessor(:custom_stylesheets) { [] }
    mattr_accessor(:custom_scripts) { [] }
    mattr_reader(:root) { (defined?(Rails) && defined?(Rails.root) && Rails.root) || Pathname(".").expand_path }
    mattr_accessor :stability_time_limit
    mattr_accessor :window_size
    mattr_accessor(:save_path) { "doc/screenshots" }
    mattr_accessor(:use_lfs)
    mattr_accessor(:screenshot_format) { "png" }
    mattr_accessor(:capybara_screenshot_options) { {} }

    class << self
      class ConsistencyConfig
        attr_accessor :css, :js,
          :normalize_css, :wait_for_fonts, :disable_animations,
          :hide_caret, :blur_active_element

        def initialize(
          css:,
          js:,
          normalize_css:,
          wait_for_fonts:,
          disable_animations:,
          hide_caret:,
          blur_active_element:
        )
          @css = css
          @js = js
          @normalize_css = normalize_css
          @wait_for_fonts = wait_for_fonts
          @disable_animations = disable_animations
          @hide_caret = hide_caret
          @blur_active_element = blur_active_element
        end

        def apply_to_screenshot!(screenshot)
          screenshot.normalize_css = normalize_css
          screenshot.wait_for_fonts = wait_for_fonts
          screenshot.disable_animations = disable_animations
          screenshot.hide_caret = hide_caret
          screenshot.blur_active_element = blur_active_element
        end
      end

      def enable_consistent_screenshots!(
        normalize_css: true,
        wait_for_fonts: true,
        disable_animations: true,
        hide_caret: true,
        blur_active_element: true
      )
        self.normalize_css = normalize_css
        self.wait_for_fonts = wait_for_fonts
        self.disable_animations = disable_animations
        self.hide_caret = hide_caret
        self.blur_active_element = blur_active_element
      end

      def configure_consistency(preset: :default)
        case preset
        when :default
          enable_consistent_screenshots!
        when :off
          enable_consistent_screenshots!(
            normalize_css: false,
            wait_for_fonts: false,
            disable_animations: false,
            hide_caret: false,
            blur_active_element: false
          )
        else
          raise ArgumentError, "Unknown consistency preset: #{preset.inspect}"
        end

        config = ConsistencyConfig.new(
          css: custom_stylesheets,
          js: custom_scripts,
          normalize_css: normalize_css,
          wait_for_fonts: wait_for_fonts,
          disable_animations: disable_animations,
          hide_caret: hide_caret,
          blur_active_element: blur_active_element
        )
        yield config if block_given?
        config.apply_to_screenshot!(self)
      end

      def root=(path)
        @@root = Pathname(path).expand_path
      end

      def active?
        enabled || (enabled.nil? && Diff.enabled)
      end

      def screenshot_area
        parts = [Screenshot.save_path]
        parts << Os.name if Screenshot.add_os_path
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
      mattr_accessor(:fail_on_difference) { true }
      mattr_accessor :color_distance_limit
      mattr_accessor(:enabled) { true }
      mattr_accessor :shift_distance_limit
      mattr_accessor :skip_area
      mattr_accessor(:driver) { :auto }
      mattr_accessor :tolerance
      mattr_accessor :perceptual_threshold

      mattr_accessor(:screenshoter) { Screenshoter }
      mattr_accessor(:manager) { CapybaraScreenshotDiff::SnapManager }

      AVAILABLE_DRIVERS = Utils.detect_available_drivers.freeze

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
        ImageCompare.new(current_path, baseline_path, default_options.merge(options))
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
