# frozen_string_literal: true

require "test_helper"
require "open3"

# ADR-005 step 1 guard: pins WHEN each config default is evaluated, per
# documented entry point, in fresh subprocesses (test_helper preloads the
# whole gem, so only a subprocess can observe require-time behavior).
#
# Current behavior being pinned:
#
# - the ENV/pwd-derived defaults (fail_if_new from ENV["CI"], root from
#   Rails.root/pwd) are evaluated ONCE, when snap_diff/config.rb is first
#   required. Mutating ENV, cwd, or Rails.root after the require -- even
#   before the first read -- must NOT change the value. A refactor that
#   turns any of these into a lazy (read-time) default, memoized or not,
#   goes red here.
# - default_options[:wait] is the opposite: it reads
#   Capybara.default_max_wait_time at CALL time, live, every call.
#
# Canonical entry points only, read through SnapDiff.config only. The v1
# entry points and the "both surfaces agree" half re-run these same scripts
# from test/legacy/legacy_config_default_timing_test.rb, which is deleted
# with the v1 trees in 2.1.
class ConfigDefaultTimingTest < ActiveSupport::TestCase
  ENTRY_POINTS = %w[
    snap_diff
    snap_diff/integrations/minitest
  ].freeze

  def run_probe(script, env)
    out, status = Open3.capture2e(env, RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, "probe failed:\n#{out}"
  end

  CHECK_HELPER = <<~'RUBY'
    def check(name, expected, actual)
      return if expected == actual
      abort("#{name}: expected #{expected.inspect}, got #{actual.inspect}")
    end
  RUBY

  # Probe A: defaults snapshot without CI/Rails + require-time freezing of
  # ENV- and pwd-derived defaults + call-time liveness of the Capybara-
  # coupled wait. ENV/cwd are mutated after the require but BEFORE the
  # first read, so both eager-at-require (current, expected) and any lazy
  # read-time variant are distinguished.
  SNAPSHOT_SCRIPT = CHECK_HELPER + <<~'RUBY'
    require "pathname"
    launch_pwd = Pathname(".").expand_path

    require ENV.fetch("PROBE_ENTRY")

    ENV["CI"] = "1"
    require "tmpdir"
    Dir.chdir(Dir.tmpdir)

    # Expected default values (CI unset, no Rails, at require time).
    # fail_if_new false / root == launch pwd also pin require-time
    # evaluation: ENV["CI"] and cwd were changed above, pre-first-read.
    {
      add_driver_path: nil,
      add_os_path: nil,
      blur_active_element: true,
      screenshot_enabled: nil,
      hide_caret: true,
      disable_animations: nil,
      root: launch_pwd,
      stability_time_limit: nil,
      window_size: nil,
      save_path: "doc/screenshots",
      use_lfs: nil,
      screenshot_format: "png",
      capybara_screenshot_options: {},
      delayed: true,
      area_size_limit: nil,
      fail_if_new: false,
      pending_if_new: false,
      fail_on_difference: true,
      color_distance_limit: nil,
      enabled: true,
      skip_area: nil,
      tolerance: nil,
      perceptual_threshold: nil,
      screenshoter: SnapDiff::Screenshoter,
      manager: SnapDiff::SnapManager
    }.each do |name, expected|
      check("SnapDiff.config.#{name}", expected, SnapDiff.config.public_send(name))
    end

    # Capybara-coupled wait is read at CALL time (live), not frozen.
    Capybara.default_max_wait_time = 42.5
    check("default_options[:wait] follows Capybara.default_max_wait_time set after require",
      42.5, SnapDiff.config.default_options[:wait])
  RUBY

  # Probe B: ENV["CI"] present (non-empty) BEFORE the require flips the
  # fail_if_new default on -- and unsetting it after the require does not
  # flip it back (frozen at require time).
  CI_SET_SCRIPT = CHECK_HELPER + <<~RUBY
    require ENV.fetch("PROBE_ENTRY")
    ENV.delete("CI")
    check(:fail_if_new, true, SnapDiff.config.fail_if_new)
  RUBY

  # Probe C: a Rails module with .root defined BEFORE the require wins over
  # the pwd fallback -- and reassigning Rails.root after the require (pre
  # first read) is not seen (frozen at require time).
  RAILS_ROOT_SCRIPT = CHECK_HELPER + <<~RUBY
    require "pathname"

    module Rails
      @root = Pathname("/fake-rails-root-at-require")
      class << self
        attr_accessor :root
      end
    end

    require ENV.fetch("PROBE_ENTRY")
    Rails.root = Pathname("/fake-rails-root-after-require")
    check(:root, Pathname("/fake-rails-root-at-require"), SnapDiff.config.root)
  RUBY

  ENTRY_POINTS.each do |entry|
    test "#{entry}: defaults snapshot matches; ENV/pwd frozen at require, wait live" do
      run_probe(SNAPSHOT_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => nil})
    end

    test "#{entry}: CI=1 before require turns fail_if_new on; unset after require does not turn it off" do
      run_probe(CI_SET_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => "1"})
    end

    test "#{entry}: Rails.root defined before require wins; reassigning it after require is not seen" do
      run_probe(RAILS_ROOT_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => nil})
    end
  end
end
