# frozen_string_literal: true

require "test_helper"
require "open3"
require "unit/config_default_timing_test" # single source of truth for the probe scripts

# LEGACY SURFACE (test/legacy/, see the Rakefile).
#
# The v1 half of config_default_timing_test.rb. Two claims, both about the
# old entry points and the old accessor view, both deleted in 3.0:
#
# 1. every legacy entry point produces the SAME require-time defaults and
#    the same freezing/liveness behaviour as the canonical ones -- proved by
#    re-running the canonical file's probe scripts verbatim under a v1
#    PROBE_ENTRY, so the two files can never drift;
# 2. every mapped setting reads identically through SnapDiff.config and
#    through its legacy mattr_accessor. Together with (1) that is exactly
#    what the old `check_both` asserted: the value is right via config, and
#    the two surfaces cannot fork.
class LegacyConfigDefaultTimingTest < ActiveSupport::TestCase
  ENTRY_POINTS = %w[
    capybara_screenshot_diff
    capybara_screenshot_diff/minitest
    capybara/screenshot/diff
  ].freeze

  def run_probe(script, env)
    out, status = Open3.capture2e(env, RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, "probe failed:\n#{out}"
  end

  BOTH_SURFACES_SCRIPT = ConfigDefaultTimingTest::CHECK_HELPER + <<~'RUBY'
    require ENV.fetch("PROBE_ENTRY")

    SnapDiff::LegacyShims::CONFIG_MAPPING.each do |name, (mod, mattr)|
      check("SnapDiff.config.#{name} vs #{mod}.#{mattr}", mod.public_send(mattr), SnapDiff.config.public_send(name))
    end
  RUBY

  ENTRY_POINTS.each do |entry|
    test "#{entry}: defaults snapshot matches; ENV/pwd frozen at require, wait live" do
      run_probe(ConfigDefaultTimingTest::SNAPSHOT_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => nil})
    end

    test "#{entry}: CI=1 before require turns fail_if_new on; unset after require does not turn it off" do
      run_probe(ConfigDefaultTimingTest::CI_SET_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => "1"})
    end

    test "#{entry}: Rails.root defined before require wins; reassigning it after require is not seen" do
      run_probe(ConfigDefaultTimingTest::RAILS_ROOT_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => nil})
    end

    test "#{entry}: every mapped setting reads the same through config and its mattr_accessor" do
      run_probe(BOTH_SURFACES_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => nil})
    end
  end
end
