# frozen_string_literal: true

# Reports which screenshot-diff drivers were detected as loadable for this run, and
# guards CI against a driver going silently missing (e.g. libvips not installed).
#
# Driver availability is detected once, at load time, via
# SnapDiff::Drivers.available — so if libvips is missing, vips-gated tests
# (see test/unit/drivers/vips_driver_test.rb) register and report as skips
# rather than failing. That's expected on a vips-less runner; this module
# exists so CI specifically (not a plain dev machine) still fails loudly when
# a driver it's supposed to have goes missing.
#
# Plain top-level module: it is test scaffolding, so it has no business
# reopening a gem namespace -- least of all the v1 one 3.0 deletes.
module DriverCoverage
  ALL_DRIVERS = %i[chunky_png vips].freeze

  def self.banner(available)
    unavailable = ALL_DRIVERS - available
    msg = "[capybara-screenshot-diff] drivers detected: #{available.join(", ")}"
    msg += " | unavailable: #{unavailable.join(", ")}" if unavailable.any?
    msg
  end

  # Drivers CI is missing but expected to have. Empty outside CI, or when an
  # expected driver was explicitly excluded (e.g. a runner that can't install
  # libvips) via the `exclude` list.
  def self.missing_for_ci(available, ci:, exclude: [])
    return [] if ci.to_s.empty?

    (ALL_DRIVERS - Array(exclude)) - available
  end
end
