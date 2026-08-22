# frozen_string_literal: true

require "capybara_screenshot_diff"
require "snap_diff/config"

# Forward-looking namespace for the gem, per ADR-004.
#
# These are pure additive aliases onto the existing
# +Capybara::Screenshot::Diff+ API — no behavior changes, no deprecation
# warnings. See ADR-004 for the full migration plan.
module SnapDiff
  Comparison = Capybara::Screenshot::Diff::ImageCompare

  def self.compare(...)
    Capybara::Screenshot::Diff.compare(...)
  end

  # v1-style configuration: yields the two existing mattr_accessor holders
  # (+Capybara::Screenshot+, +Capybara::Screenshot::Diff+) exactly as
  # +Capybara::Screenshot::Diff.configure+ always has. Kept byte-for-byte
  # identical to +Diff.configure+ for existing callers migrating namespaces
  # without changing call shape.
  #
  #   SnapDiff.start do |screenshot, diff|
  #     screenshot.window_size = [1280, 1024]
  #     diff.tolerance = 0.0005
  #   end
  def self.start(&block)
    Capybara::Screenshot::Diff.configure(&block)
  end

  # Forward-looking configuration: yields the single consolidated
  # {SnapDiff::Config} object instead of the two old holders. Same
  # underlying storage as +start+ / the old mattr_accessors -- this is a
  # different *shape* of the same settings, not a second source of truth.
  #
  #   SnapDiff.configure do |config|
  #     config.window_size = [1280, 1024]
  #     config.tolerance = 0.0005
  #   end
  def self.configure
    yield config
  end

  # The single consolidated settings object. See {SnapDiff::Config}.
  def self.config
    @config ||= Config.new
  end
end
