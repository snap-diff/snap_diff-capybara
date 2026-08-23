# frozen_string_literal: true

require "test_helper"
require "open3"
require "minitest/stub_const"

# SnapDiff::Drivers is the canonical driver registry (docs/snapdiff.md).
# Until 3.0 readiness work, `.available` read the value out of
# SnapDiff::Drivers::AVAILABLE_DRIVERS, which is defined by
# config_legacy.rb -- so a documented canonical API only worked when the v1
# tree happened to be loaded.
class DriversTest < ActiveSupport::TestCase
  # The regression: `require "snap_diff/drivers"` alone used to raise
  # `NameError: uninitialized constant Capybara::Screenshot::Diff` here.
  # test_helper preloads the whole gem, so only a fresh process can catch it.
  test ".available answers after requiring snap_diff/drivers and nothing else" do
    script = <<~RUBY
      require "snap_diff/drivers"
      drivers = SnapDiff::Drivers.available
      abort("not an Array: \#{drivers.inspect}") unless drivers.is_a?(Array)
      # ...and it answered on its own, without config_legacy.rb being loaded.
      # (Constants alone would not prove it: bundler/setup evaluates the
      # gemspec, which loads the legacy version.rb and so defines
      # Capybara::Screenshot::Diff in any subprocess.)
      legacy = $LOADED_FEATURES.grep(/config_legacy\\.rb\\z/)
      abort("config_legacy got loaded: \#{legacy.join(", ")}") unless legacy.empty?
    RUBY

    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, "expected standalone snap_diff/drivers to answer .available, got:\n#{out}"
  end

  test ".available reads the constant live, so it stays stubbable" do
    SnapDiff::Drivers.stub_const(:AVAILABLE_DRIVERS, []) do
      assert_empty SnapDiff::Drivers.available
    end

    assert_equal SnapDiff::Drivers::AVAILABLE_DRIVERS, SnapDiff::Drivers.available
  end

  # Ported from namespace_forwarding_test (test/legacy/), which was the only
  # place pinning this: it asserted the v1 LOADED_DRIVERS constant is the
  # same object as this hash and that a registration through it shows up
  # here. The v1 half dies in 3.0; the canonical half -- .loaded is ONE
  # memoized hash, mutated in place, so a driver registered into it stays
  # registered (Utils.find_driver_class_for caches through it) -- must not.
  test ".loaded is a single hash mutated in place, so registrations stick" do
    assert_same SnapDiff::Drivers.loaded, SnapDiff::Drivers.loaded

    SnapDiff::Drivers.loaded[:registry_probe] = :probe_driver

    assert_equal :probe_driver, SnapDiff::Drivers.loaded[:registry_probe]
  ensure
    SnapDiff::Drivers.loaded.delete(:registry_probe)
  end

  test "detection is reachable under both the canonical and the documented Utils name" do
    assert_equal SnapDiff::Drivers.detect_available, SnapDiff::Utils.detect_available_drivers
  end

  # Naming a driver class must work without a prior require (the leaves are
  # autoloaded), but ONLY for drivers this process can actually load.
  # Neither driver gem is a runtime dependency, and the documented v1
  # pattern is `driver = :vips if defined?(...Drivers::VipsDriver)`: an
  # unconditional autoload makes that truthy on a box without ruby-vips and
  # the branch then dies on const_get. v1.12.0 loaded vips_driver.rb only
  # from find_driver_class_for, so `defined?` was nil there.
  test "an unavailable driver leaf stays undefined rather than autoloading into a crash" do
    script = <<~RUBY
      module Kernel
        alias_method :__real_require, :require
        def require(name)
          raise LoadError, "cannot load such file -- vips" if name == "vips"
          __real_require(name)
        end
      end
      require "snap_diff/drivers"

      abort("vips reported available") if SnapDiff::Drivers.available.include?(:vips)
      abort("VipsDriver is const_defined? without ruby-vips") if
        SnapDiff::Drivers.const_defined?(:VipsDriver)
      abort("chunky_png leaf should still autoload") unless
        SnapDiff::Drivers::ChunkyPNGDriver.is_a?(Class)
    RUBY

    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, out
  end
end
