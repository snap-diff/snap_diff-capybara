# frozen_string_literal: true

# See the matching comment in integrations/minitest.rb.
require_relative "../dsl"
require "snap_diff/screenshot_assertion"
require "snap_diff/reporting"

World(::SnapDiff::DSL)

Before do
  SnapDiff.config.delayed = false
  SnapDiff::BrowserHelpers.resize_window_if_needed
end

After do |scenario|
  if !scenario.failed? && (msg = SnapDiff.pending_screenshots_message)
    skip_this_scenario(msg)
  end
ensure
  SnapDiff.reset
end

AfterAll { SnapDiff::Reporting.finalize! }
