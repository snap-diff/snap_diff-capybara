# frozen_string_literal: true

require "snap_diff/deprecation"
require "snap_diff/drivers"

# ADR-004 v2 step 6: const_missing-based forwarders for the pre-v2
# namespaces. Every old-name lookup below resolves -- lazily -- to the exact
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
# - Capybara::Screenshot::Diff::VERSION: the gemspec resolves it at build
#   time; a lazy shim would make every `gem build` warn.
# - Drivers::ChunkyPNGDriver / Drivers::VipsDriver: real constants on the
#   shared SnapDiff::Drivers module (the Drivers alias is same-object by
#   contract), so const_missing can never fire for the leaf names;
#   resolving them through the old path still warns for ...::Drivers.
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

        Deprecation.warn("#{old_prefix}::#{name}", target, category: :constant)
        Object.const_get(target)
      end
    end
  end
end

module Capybara
  module Screenshot
    module Diff
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

# BaseDriver dissolved into the SnapDiff::Driver mixin (v2 step 4); the
# Drivers alias is same-object, so the hook has to live on SnapDiff::Drivers
# itself. `class MyDriver < BaseDriver` becomes `include SnapDiff::Driver`.
SnapDiff::LegacyShims.install(SnapDiff::Drivers, "Capybara::Screenshot::Diff::Drivers", {
  BaseDriver: "SnapDiff::Driver"
}.freeze)
