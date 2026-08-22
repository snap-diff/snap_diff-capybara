# frozen_string_literal: true

# Dual-install guard: capybara-screenshot-diff and snap_diff-capybara ship
# identical files. With BOTH activated, every require silently resolves
# from whichever gem activated first, so version skew between the two is
# undetectable. Refuse that setup at the entry point. Local dev from
# source loads neither spec, so the guard fires only when both are
# genuinely installed as gems.
module SnapDiff
  DualInstallError = Class.new(StandardError)

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

# None of these requires ever leads back to this file: config_legacy sits
# just above the snap_diff/config leaf (see both headers -- since ADR-008
# step 1 the storage leaf is snap_diff/config, which config_legacy
# requires), the image_compare forwarder pulls in
# snap_diff/comparison plus the legacy const_missing shims, and
# "capybara/dsl" is the base gem. That keeps this file's require graph
# acyclic -- it never requires "capybara_screenshot_diff" back, unlike the
# old autoload-based wiring this replaced. The forwarder path (not
# "snap_diff/comparison" directly) is deliberate: it installs
# snap_diff/legacy_shims, so the old Capybara::Screenshot::Diff constants
# stay resolvable (now with deprecation warnings) even in processes that
# only ever require "snap_diff".
# "capybara/dsl" is needed directly (not just transitively) so
# `Capybara.default_max_wait_time` in Diff.default_options resolves even
# when "snap_diff" is required standalone (SnapDiffTest's
# "standalone-loadable in a fresh process" regression test).
require "capybara/dsl"
require "capybara/screenshot/diff/config_legacy"
require "capybara/screenshot/diff/image_compare"
require "snap_diff/config"

# Forward-looking namespace for the gem, per ADR-004.
#
# Since v2 step 5 the comparison implementation lives here
# ({SnapDiff::Comparison}, {SnapDiff::ComparisonResult}); since step 6 the
# old +Capybara::Screenshot::Diff+ constants are same-object const_missing
# shims (snap_diff/legacy_shims) that emit a deprecation warning once per
# constant per process. See ADR-004 for the full migration plan.
module SnapDiff
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

  # SnapDiff.config itself is defined in snap_diff/config.rb (the storage
  # leaf), where the Config instance is created eagerly at require time so
  # the ENV["CI"] / Rails.root defaults evaluate at load, not first call.
end
