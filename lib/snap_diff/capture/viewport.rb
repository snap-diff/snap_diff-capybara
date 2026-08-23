# frozen_string_literal: true

require_relative "../browser_helpers"

module SnapDiff
  module Capture
    # Per-capture viewport preparation seam.
    #
    # Called exactly once per capture, before the screenshoter runs and outside
    # any stability retry loop. It only validates the window size
    # (raise-only, never resizes).
    module Viewport
      module_function

      # @param expected_window_size [Array(Integer, Integer), nil] the configured window size
      # @raise [SnapDiff::WindowSizeMismatchError] if the browser
      #   window does not match the expected size.
      def prepare!(expected_window_size)
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
