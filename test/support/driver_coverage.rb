# frozen_string_literal: true

module CapybaraScreenshotDiff
  # Reports which screenshot-diff drivers were detected as loadable for this run, and
  # guards CI against a driver going silently missing (e.g. libvips not installed).
  #
  # Driver availability is detected once, at load time, via
  # Capybara::Screenshot::Diff::AVAILABLE_DRIVERS — so if libvips is missing,
  # vips-only tests never get defined (see test/unit/drivers/vips_driver_test.rb)
  # and vips-gated tests elsewhere silently skip instead of failing. Neither shows
  # up as a failure, which is how a 232-run/0-skip environment and a
  # 194-run/11-skip environment can both look "green".
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
end
