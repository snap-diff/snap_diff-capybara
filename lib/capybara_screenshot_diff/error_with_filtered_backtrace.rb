# frozen_string_literal: true

require "capybara_screenshot_diff/backtrace_filter"

module CapybaraScreenshotDiff
  # @private
  class ErrorWithFilteredBacktrace < StandardError
    # @private
    def initialize(message = nil, backtrace = [])
      super(message)
      filter = BacktraceFilter.new
      set_backtrace(filter.filtered(backtrace))
    end
  end
end
