# frozen_string_literal: true

# Legacy-name forwarder: the module alias in capybara/screenshot/diff/drivers.rb
# makes VipsDriver reachable as Capybara::Screenshot::Diff::Drivers::VipsDriver.
require "capybara/screenshot/diff/drivers"
require "snap_diff/drivers/vips_driver"
