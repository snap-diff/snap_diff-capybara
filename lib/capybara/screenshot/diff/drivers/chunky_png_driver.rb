# frozen_string_literal: true

# Forwarder (ADR-004 v2 step 4): ChunkyPNGDriver lives in SnapDiff::Drivers
# now; the module alias in capybara/screenshot/diff/drivers.rb makes it
# reachable as Capybara::Screenshot::Diff::Drivers::ChunkyPNGDriver.
require "capybara/screenshot/diff/drivers"
require "snap_diff/drivers/chunky_png_driver"
