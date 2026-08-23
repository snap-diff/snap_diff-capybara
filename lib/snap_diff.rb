# frozen_string_literal: true

# Dual-install guard: capybara-screenshot-diff and snap_diff-capybara ship
# identical files. With BOTH activated, every require silently resolves
# from whichever gem activated first, so version skew between the two is
# undetectable. Refuse that setup at the entry point. Local dev from
# source loads neither spec, so the guard fires only when both are
# genuinely installed as gems.
#
# snap_diff/errors is pulled in first (two dependency-free files) so
# DualInstallError can sit under SnapDiff::Error like every other error the
# gem raises -- docs/snapdiff.md promises Error is the catch-all.
require "snap_diff/errors"

module SnapDiff
  DualInstallError = Class.new(Error)

  # @api private
  def self.assert_single_gem!(loaded_specs = Gem.loaded_specs)
    return unless loaded_specs.key?("capybara-screenshot-diff") && loaded_specs.key?("snap_diff-capybara")

    raise DualInstallError,
      "Both `capybara-screenshot-diff` and `snap_diff-capybara` gems are installed. " \
      "They ship identical files, so files load from whichever gem activated first " \
      "and versions can silently diverge. Remove one of them from your Gemfile."
  end
end
SnapDiff.assert_single_gem!

# "capybara/dsl" is needed directly (not just transitively) so
# `Capybara.default_max_wait_time` in Config#default_options resolves even
# when "snap_diff" is required standalone (SnapDiffTest's
# "standalone-loadable in a fresh process" regression test).
require "capybara/dsl"
require "snap_diff/config"
require "snap_diff/comparison"
require "snap_diff/version"
# SnapDiff.session/.reset/.pending_screenshots_message are part of the
# documented core surface (docs/snapdiff.md object map lists them with no
# extra require), so the entry point owns them rather than leaving them to
# whichever integration happens to be loaded.
require "snap_diff/screenshot_assertion"

# The canonical namespace for the gem.
module SnapDiff
  # Compare two images on disk with the configured defaults.
  #
  # Note the argument order swap: callers pass baseline first (reading
  # "compare baseline against current"), Comparison takes current first.
  def self.compare(baseline_path, current_path, **options)
    Comparison.new(current_path, baseline_path, config.default_options.merge(options))
  end

  # The single configuration entry point (ADR-008): yields the one
  # consolidated {SnapDiff::Config} object. The v1 two-holder block
  # (+SnapDiff.start+) was removed with the legacy trees in 2.1.
  #
  #   SnapDiff.configure do |config|
  #     config.window_size = [1280, 1024]
  #     config.tolerance = 0.0005
  #   end
  def self.configure
    yield config
  end

  # SnapDiff.config itself is defined in snap_diff/config.rb (the storage
  # leaf), where the Config instance is created eagerly at require time so
  # the ENV["CI"] / Rails.root defaults evaluate at load, not first call.
end
