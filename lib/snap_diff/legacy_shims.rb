# frozen_string_literal: true

require "snap_diff/comparison"
require "snap_diff/config"
require "snap_diff/deprecation"
require "snap_diff/drivers"
require "snap_diff/version"

# THE v1 compatibility surface, in one file -- and the whole of it that is
# code. lib/capybara* is alias-only by contract
# (legacy_tree_is_alias_only_test.rb) and the canonical core names nothing
# from it (core_tree_has_no_legacy_deps_test.rb), so this file plus those
# trees is exactly what 3.0 deletes.
#
# Three things live here:
#   1. the const_missing forwarders for the pre-v2 namespaces (below);
#   2. CONFIG_MAPPING -- the old mattr_accessor surface, generated as thin
#      delegators onto SnapDiff.config (which owns the storage);
#   3. the derived/config forwarders that used to sit in config_legacy.rb
#      (Screenshot.active?, Diff.configure, SnapDiff.start, ...).
#
# 2 and 3 moved here so `require "snap_diff"` can keep offering the full v1
# surface -- as it always has -- without the core requiring anything from
# lib/capybara/.
#
# const_missing-based forwarders for the pre-v2 namespaces. Every old-name
# lookup below resolves -- lazily -- to the exact
# same object as its SnapDiff:: replacement (identity pinned by
# test/unit/namespace_forwarding_test.rb) and emits a deprecation warning,
# once per constant per process, silenceable via
# SnapDiff.silence_deprecations or SNAP_DIFF_SILENCE_DEPRECATIONS=1.
#
# Deliberately eager-and-silent exceptions (plain constants, defined by
# their own forwarder files, never warn):
#
# - Capybara::Screenshot::Os and CapybaraScreenshotDiff::DSL (and the
#   unmapped CapybaraScreenshotDiff::Minitest::Assertions): advertised
#   entry-point constants probed with Object.const_defined? by
#   support_load_probe_test.rb -- const_defined? never triggers
#   const_missing, so a lazy shim would break that contract.
# - Capybara::Screenshot::Diff::VERSION, and ::Comparison (the images
#   struct): documented user-facing names that adopters feature-detect with
#   defined?/const_defined?. Both are assigned eagerly BELOW rather than by
#   their own forwarder files (version.rb, image_compare.rb): the core
#   stopped requiring those forwarders in the 3.0-readiness pass, so nothing
#   loaded them under a canonical entry point and both names silently
#   vanished from six of them. This file is required by every entry point,
#   canonical and legacy, so it is the only place the eager exceptions can
#   actually be eager.
# - Capybara::Screenshot::Diff::Reporters::Default (a documented subclassing
#   extension point): same reasoning, but its forwarder
#   (reporters/default.rb) is still loaded on every path that defines
#   ::Reporters at all, so the assignment stays there.
# - Drivers::ChunkyPNGDriver / Drivers::VipsDriver: real constants on the
#   shared SnapDiff::Drivers module (the Drivers alias is same-object by
#   contract), so const_missing can never fire for the leaf names;
#   resolving them through the old path still warns for ...::Drivers.
# - Diff::LOADED_DRIVERS: user code registers custom drivers by mutating
#   this hash in place, so it must be the exact same object as the
#   canonical SnapDiff::Drivers.loaded -- a lazy warn-once shim could not
#   keep a mutable alias, and warning on a supported registration surface
#   would be noise. Assigned eagerly below.
# - Diff::AVAILABLE_DRIVERS: stays a real constant, aliased BELOW from the
#   canonical SnapDiff::Drivers::AVAILABLE_DRIVERS (same object;
#   SnapDiff::Drivers.available is the canonical reader, and its constant is
#   the stubbing point -- stubbing this alias only rebinds the alias).

# The v1 namespaces, predefined empty so CONFIG_MAPPING can name them at
# class-body eval time. Everything below reopens them.
module Capybara
  module Screenshot
    module Diff
    end
  end
end

module SnapDiff
  # @api private
  module LegacyShims
    # Installs a warn-then-forward const_missing on +namespace+.
    #
    # @param namespace [Module] the old namespace to hook
    # @param old_prefix [String] how the old constant path reads to a human
    # @param mapping [Hash{Symbol => String}] old leaf name => new full name
    def self.install(namespace, old_prefix, mapping)
      namespace.define_singleton_method(:const_missing) do |name|
        target = mapping[name]
        return super(name) unless target

        Deprecation.warn("#{old_prefix}::#{name}", target)
        Object.const_get(target)
      end
    end

    # config attr name => [legacy module, legacy accessor name].
    # The keys are exactly SnapDiff::Config::SETTINGS; this hash only says
    # which of the two legacy holders each one used to hang off, and under
    # what name (only +screenshot_enabled+ differs -- see Config::SETTINGS).
    CONFIG_MAPPING = {
      # Capybara::Screenshot
      add_driver_path: [Capybara::Screenshot, :add_driver_path],
      add_os_path: [Capybara::Screenshot, :add_os_path],
      blur_active_element: [Capybara::Screenshot, :blur_active_element],
      screenshot_enabled: [Capybara::Screenshot, :enabled],
      hide_caret: [Capybara::Screenshot, :hide_caret],
      disable_animations: [Capybara::Screenshot, :disable_animations],
      root: [Capybara::Screenshot, :root],
      stability_time_limit: [Capybara::Screenshot, :stability_time_limit],
      window_size: [Capybara::Screenshot, :window_size],
      save_path: [Capybara::Screenshot, :save_path],
      use_lfs: [Capybara::Screenshot, :use_lfs],
      screenshot_format: [Capybara::Screenshot, :screenshot_format],
      capybara_screenshot_options: [Capybara::Screenshot, :capybara_screenshot_options],
      # Capybara::Screenshot::Diff
      delayed: [Capybara::Screenshot::Diff, :delayed],
      area_size_limit: [Capybara::Screenshot::Diff, :area_size_limit],
      fail_if_new: [Capybara::Screenshot::Diff, :fail_if_new],
      pending_if_new: [Capybara::Screenshot::Diff, :pending_if_new],
      fail_on_difference: [Capybara::Screenshot::Diff, :fail_on_difference],
      color_distance_limit: [Capybara::Screenshot::Diff, :color_distance_limit],
      enabled: [Capybara::Screenshot::Diff, :enabled],
      shift_distance_limit: [Capybara::Screenshot::Diff, :shift_distance_limit],
      skip_area: [Capybara::Screenshot::Diff, :skip_area],
      driver: [Capybara::Screenshot::Diff, :driver],
      tolerance: [Capybara::Screenshot::Diff, :tolerance],
      perceptual_threshold: [Capybara::Screenshot::Diff, :perceptual_threshold],
      screenshoter: [Capybara::Screenshot::Diff, :screenshoter],
      manager: [Capybara::Screenshot::Diff, :manager]
    }.freeze

    # Installs the old mattr_accessor surface onto the legacy modules,
    # delegating to the single storage in SnapDiff.config. mattr_accessor
    # used to define both singleton and instance accessors (the instance
    # ones are what `include Capybara::Screenshot::Diff` picks up), so both
    # are installed. root keeps its historical asymmetry -- readable
    # everywhere, writable only at module level (it was mattr_reader plus a
    # custom module-level writer) -- with the Pathname coercion living in
    # Config#root=.
    def self.install_config_accessors
      CONFIG_MAPPING.each do |name, (mod, mattr)|
        [mod, mod.singleton_class].each do |target|
          target.define_method(mattr) { SnapDiff.config.public_send(name) }
          next if name == :root && target == mod

          target.define_method(:"#{mattr}=") { |value| SnapDiff.config.public_send(:"#{name}=", value) }
        end
      end
    end
  end
end

SnapDiff::LegacyShims.install_config_accessors

module SnapDiff
  # v1-style configuration: yields the two legacy accessor holders
  # (+Capybara::Screenshot+, +Capybara::Screenshot::Diff+) exactly as
  # +Capybara::Screenshot::Diff.configure+ always has -- and, since ADR-008
  # step 7b, this is where that yield actually happens; Diff.configure
  # forwards here. Both names stay identical in call shape.
  #
  #   SnapDiff.start do |screenshot, diff|
  #     screenshot.window_size = [1280, 1024]
  #     diff.tolerance = 0.0005
  #   end
  #
  # Defined in this file, not snap_diff.rb, because the two holders it
  # yields ARE the v1 surface: it cannot outlive them. The consolidated
  # shape, SnapDiff.configure, is the canonical one and lives in the core.
  def self.start
    yield Capybara::Screenshot, Capybara::Screenshot::Diff
  end
end

module Capybara
  module Screenshot
    # Derived config, ex config_legacy.rb: one-line forwarders onto the
    # canonical implementations in SnapDiff::Config (ADR-008 step 7b).
    class << self
      def active?
        SnapDiff.config.active?
      end

      def screenshot_area
        SnapDiff.config.screenshot_area
      end

      def screenshot_area_abs
        SnapDiff.config.screenshot_area_abs
      end
    end

    module Diff
      # EAGER same-object aliases of canonical values (see header for why
      # each one is eager rather than a warn-once const_missing shim).
      LOADED_DRIVERS = SnapDiff::Drivers.loaded
      AVAILABLE_DRIVERS = SnapDiff::Drivers::AVAILABLE_DRIVERS
      Comparison = SnapDiff::Comparison::Images
      VERSION = SnapDiff::VERSION

      # Configure screenshot and diff settings in one block.
      #
      #   Capybara::Screenshot::Diff.configure do |screenshot, diff|
      #     screenshot.window_size = [1280, 1024]
      #     screenshot.stability_time_limit = 1
      #     diff.driver = :vips
      #     diff.tolerance = 0.0005
      #   end
      # The bare `yield` (rather than an explicit &block) keeps this
      # method's published arity byte-identical to what it always had.
      def self.configure
        SnapDiff.start { |screenshot, diff| yield screenshot, diff }
      end

      def self.compare(baseline_path, current_path, **options)
        SnapDiff.compare(baseline_path, current_path, **options)
      end

      def self.default_options
        SnapDiff.config.default_options
      end
    end
  end
end

module CapybaraScreenshotDiff
  module Reporters
  end
end

SnapDiff::LegacyShims.install(Capybara::Screenshot, "Capybara::Screenshot", {
  BrowserHelpers: "SnapDiff::BrowserHelpers",
  Screenshoter: "SnapDiff::Screenshoter"
}.freeze)

SnapDiff::LegacyShims.install(Capybara::Screenshot::Diff, "Capybara::Screenshot::Diff", {
  Vcs: "SnapDiff::Vcs",
  StableScreenshoter: "SnapDiff::StableScreenshoter",
  ImagePreprocessor: "SnapDiff::ImagePreprocessor",
  AreaCalculator: "SnapDiff::AreaCalculator",
  AnnotationService: "SnapDiff::AnnotationService",
  Utils: "SnapDiff::Utils",
  ScreenshotMatcher: "SnapDiff::ScreenshotMatcher",
  Drivers: "SnapDiff::Drivers",
  ImageCompare: "SnapDiff::Comparison",
  Difference: "SnapDiff::ComparisonResult"
}.freeze)

SnapDiff::LegacyShims.install(CapybaraScreenshotDiff, "CapybaraScreenshotDiff", {
  RED_RGBA: "SnapDiff::RED_RGBA",
  ORANGE_RGBA: "SnapDiff::ORANGE_RGBA",
  SnapManager: "SnapDiff::SnapManager",
  Snap: "SnapDiff::Snap",
  ScreenshotNamer: "SnapDiff::ScreenshotNamer",
  AttemptsReporter: "SnapDiff::AttemptsReporter",
  BacktraceFilter: "SnapDiff::BacktraceFilter",
  ErrorWithFilteredBacktrace: "SnapDiff::ErrorWithFilteredBacktrace",
  ScreenshotAssertion: "SnapDiff::ScreenshotAssertion",
  AssertionRegistry: "SnapDiff::AssertionRegistry"
}.freeze)

SnapDiff::LegacyShims.install(CapybaraScreenshotDiff::Reporters, "CapybaraScreenshotDiff::Reporters", {
  HTML: "SnapDiff::Reporters::HTML"
}.freeze)

# BaseDriver dissolved into the SnapDiff::Driver mixin; the Drivers alias is
# same-object, so the hook has to live on SnapDiff::Drivers itself.
# `class MyDriver < BaseDriver` becomes `include SnapDiff::Driver`.
SnapDiff::LegacyShims.install(SnapDiff::Drivers, "Capybara::Screenshot::Diff::Drivers", {
  BaseDriver: "SnapDiff::Driver"
}.freeze)
