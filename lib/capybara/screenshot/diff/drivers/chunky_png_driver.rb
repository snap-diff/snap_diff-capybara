# frozen_string_literal: true

# Legacy-name forwarder: the module alias in capybara/screenshot/diff/drivers.rb
# makes ChunkyPNGDriver reachable as
# Capybara::Screenshot::Diff::Drivers::ChunkyPNGDriver.
require "capybara/screenshot/diff/drivers"
require "snap_diff/drivers/chunky_png_driver"
