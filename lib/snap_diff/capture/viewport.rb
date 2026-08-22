# frozen_string_literal: true

require_relative "../browser_helpers"

module SnapDiff
  module Capture
    # Per-capture viewport preparation seam.
    #
    # Called exactly once per capture, before the screenshoter runs and outside
    # any stability retry loop. Today it only validates the window size
    # (raise-only, never resizes) — the same guard ScreenshotMatcher carried
    # inline before. v3 hangs scroll-position preservation and element-anchored
    # capture off this seam via the +anchor+ parameter without touching callers.
    module Viewport
      module_function

      # @param expected_window_size [Array(Integer, Integer), nil] the configured window size
      # @param anchor [Object, nil] reserved for v3 (scroll preservation /
      #   element-anchored capture); accepted but unused today.
      # @raise [SnapDiff::WindowSizeMismatchError] if the browser
      #   window does not match the expected size.
      def prepare!(expected_window_size, anchor: nil)
        return unless BrowserHelpers.window_size_is_wrong?(expected_window_size)

        current_size = BrowserHelpers.selenium? ?
          BrowserHelpers.session.driver.browser.manage.window.size.to_s :
          "unknown"

        raise SnapDiff::WindowSizeMismatchError.new(<<~ERROR.chomp, caller)
          Window size mismatch detected!
          Expected: #{expected_window_size.inspect}
          Actual: #{current_size}

          Screenshots cannot be compared when window sizes don't match.
          Please ensure the browser window is properly sized before taking screenshots.
        ERROR
      end
    end
  end
end
