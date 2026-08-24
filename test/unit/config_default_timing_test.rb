# frozen_string_literal: true

require "test_helper"
require "open3"

# ADR-005 step 1 guard: pins WHEN each config default is evaluated, per
# documented entry point, in fresh subprocesses (test_helper preloads the
# whole gem, so only a subprocess can observe require-time behavior).
#
# Current behavior being pinned:
#
# - the pwd-derived default (root, from Rails.root/pwd) is evaluated ONCE,
#   when snap_diff/config.rb is first required. Mutating cwd or Rails.root
#   after the require -- even before the first read -- must NOT change the
#   value. A refactor that turns it into a lazy (read-time) default,
#   memoized or not, goes red here.
# - default_options[:wait] is the opposite: it reads
#   Capybara.default_max_wait_time at CALL time, live, every call.
# - fail_if_new is live too, and deliberately so: it has no stored default,
#   so an unset one asks ENV["CI"] on every read while an explicit setting
#   outranks the environment. That is the whole point -- a frozen sniff
#   cannot tell "the user asked for false" from "CI was absent at require".
#   See CI_PRECEDENCE_SCRIPT and snap_diff_config_test.rb.
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

    require "tmpdir"
    Dir.chdir(Dir.tmpdir)

    # Expected default values (CI unset, no Rails, at require time).
    # root == launch pwd also pins require-time evaluation: cwd was changed
    # above, pre-first-read.
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
      shift_distance_limit: nil,
      skip_area: nil,
      driver: :auto,
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

    # fail_if_new is live too: CI appearing after the require is seen.
    ENV["CI"] = "1"
    check("fail_if_new follows ENV['CI'] set after require", true, SnapDiff.config.fail_if_new)
  RUBY

  # Probe B: fail_if_new precedence. The ENV["CI"] sniff is the FALLBACK,
  # read live in both directions; an explicit setting outranks it whenever
  # the variable appears (insta#924, jest#12288). Entered with CI=1 set
  # before the require, so a require-time freeze is distinguishable.
  CI_PRECEDENCE_SCRIPT = CHECK_HELPER + <<~RUBY
    require ENV.fetch("PROBE_ENTRY")
    check("CI=1 at require", true, SnapDiff.config.fail_if_new)

    ENV.delete("CI")
    check("CI unset after require is seen", false, SnapDiff.config.fail_if_new)

    ENV["CI"] = "1"
    SnapDiff.config.fail_if_new = false
    check("explicit false outranks CI=1", false, SnapDiff.config.fail_if_new)

    ENV.delete("CI")
    SnapDiff.config.fail_if_new = true
    check("explicit true outranks CI unset", true, SnapDiff.config.fail_if_new)

    ENV["CI"] = "1"
    SnapDiff.config.fail_if_new = nil
    check("nil hands it back to the environment", true, SnapDiff.config.fail_if_new)
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
    test "#{entry}: defaults snapshot matches; pwd frozen at require, wait and fail_if_new live" do
      run_probe(SNAPSHOT_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => nil})
    end

    test "#{entry}: an explicit fail_if_new outranks ENV['CI'], which is otherwise read live" do
      run_probe(CI_PRECEDENCE_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => "1"})
    end

    test "#{entry}: Rails.root defined before require wins; reassigning it after require is not seen" do
      run_probe(RAILS_ROOT_SCRIPT, {"PROBE_ENTRY" => entry, "CI" => nil})
    end
  end
end
