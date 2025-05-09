# frozen_string_literal: true

require_relative "standard_capture_strategy"
require_relative "stable_capture_strategy"

module Capybara
  module Screenshot
    module Diff
      # Orchestrates the selection of a capture strategy based on capture and
      # comparison options. This replaces the previous ScreenshotTaker factory.
      module ScreenshotCoordinator
        module_function

        # Unified public API to obtain a comparison screenshot.
        #
        # Usage (internal):
        #   ScreenshotCoordinator.capture(full_name, capture_options, comparison_options)
        #
        # @param snap_or_name [CapybaraScreenshotDiff::Snap, String]
        # @param capture_options [Hash]
        # @param comparison_options [Hash]
        # @return [CapybaraScreenshotDiff::Snap]
        def capture(snap_or_name, capture_options, comparison_options)
          snap = ensure_snap(snap_or_name, capture_options)
          strategy(capture_options, comparison_options).take_comparison_screenshot(snap)
          snap
        end

        # ------------------------------------------------------------------
        def strategy(capture_options, comparison_options)
          strategy_klass = capture_options[:stability_time_limit] ? StableCaptureStrategy : StandardCaptureStrategy
          strategy_klass.new(capture_options, comparison_options)
        end

        private_class_method :strategy

        def ensure_snap(snap_or_name, capture_options)
          return snap_or_name if snap_or_name.is_a?(CapybaraScreenshotDiff::Snap)

          CapybaraScreenshotDiff::SnapManager.snapshot(
            snap_or_name,
            capture_options[:screenshot_format] || "png"
          )
        end

        private_class_method :ensure_snap
      end
    end
  end
end
