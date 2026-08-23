# frozen_string_literal: true

require "test_helper"
require "open3"
require "minitest/stub_const"

# SnapDiff::Drivers is the canonical driver registry (docs/snapdiff.md).
# Until 3.0 readiness work, `.available` read the value out of
# Capybara::Screenshot::Diff::AVAILABLE_DRIVERS, which is defined by
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

  test "detection is reachable under both the canonical and the documented Utils name" do
    assert_equal SnapDiff::Drivers.detect_available, SnapDiff::Utils.detect_available_drivers
  end
end
