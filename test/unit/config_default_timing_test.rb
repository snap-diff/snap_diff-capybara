# frozen_string_literal: true

require "test_helper"
require "open3"

# ADR-005 step 1 guard: pins WHEN each config default is evaluated, per
# documented entry point, in fresh subprocesses (test_helper preloads the
# whole gem, so only a subprocess can observe require-time behavior).
#
# Current behavior being pinned (the coming storage inversion must not
# shift any of these):
#
# - mattr_accessor block defaults (fail_if_new from ENV["CI"], root from
#   Rails.root/pwd) are evaluated ONCE, at class-body eval time, when
#   config_legacy.rb is first required. Mutating ENV, cwd, or Rails.root
#   after the require -- even before the first read -- must NOT change the
#   value. A refactor that turns any of these into a lazy (read-time)
#   default, memoized or not, goes red here.
# - Diff.default_options[:wait] is the opposite: it reads
#   Capybara.default_max_wait_time at CALL time, live, every call.
#
# Value snapshots are asserted through BOTH surfaces (SnapDiff.config.x
# and the legacy mattr_accessor) so the inversion can't silently fork them.
class ConfigDefaultTimingTest < ActiveSupport::TestCase
  ENTRY_POINTS = %w[
    capybara_screenshot_diff
    capybara_screenshot_diff/minitest
    snap_diff
    capybara/screenshot/diff
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

    def check_both(name, expected, mod, mattr)
      check("#{mod}.#{mattr}", expected, mod.public_send(mattr))
      check("SnapDiff.config.#{name}", expected, SnapDiff.config.public_send(name))
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

    # 1) Every mapped setting reads the same through both surfaces.
    SnapDiff::LegacyShims::CONFIG_MAPPING.each do |name, (mod, mattr)|
      check("SnapDiff.config.#{name} vs #{mod}.#{mattr}", mod.public_send(mattr), SnapDiff.config.public_send(name))
    end

    # 2) Expected default values (CI unset, no Rails, at require time).
    #    fail_if_new false / root == launch pwd also pin require-time
    #    evaluation: ENV["CI"] and cwd were changed above, pre-first-read.
    screenshot = Capybara::Screenshot
    diff = Capybara::Screenshot::Diff
    {
      add_driver_path: [nil, screenshot, :add_driver_path],
      add_os_path: [nil, screenshot, :add_os_path],
      blur_active_element: [true, screenshot, :blur_active_element],
      screenshot_enabled: [nil, screenshot, :enabled],
      hide_caret: [true, screenshot, :hide_caret],
      disable_animations: [nil, screenshot, :disable_animations],
      root: [launch_pwd, screenshot, :root],
      stability_time_limit: [nil, screenshot, :stability_time_limit],
      window_size: [nil, screenshot, :window_size],
      save_path: ["doc/screenshots", screenshot, :save_path],
      use_lfs: [nil, screenshot, :use_lfs],
      screenshot_format: ["png", screenshot, :screenshot_format],
      capybara_screenshot_options: [{}, screenshot, :capybara_screenshot_options],
      delayed: [true, diff, :delayed],
      area_size_limit: [nil, diff, :area_size_limit],
      fail_if_new: [false, diff, :fail_if_new],
      pending_if_new: [false, diff, :pending_if_new],
      fail_on_difference: [true, diff, :fail_on_difference],
      color_distance_limit: [nil, diff, :color_distance_limit],
      enabled: [true, diff, :enabled],
      shift_distance_limit: [nil, diff, :shift_distance_limit],
      skip_area: [nil, diff, :skip_area],
      driver: [:auto, diff, :driver],
      tolerance: [nil, diff, :tolerance],
      perceptual_threshold: [nil, diff, :perceptual_threshold],
      screenshoter: [SnapDiff::Screenshoter, diff, :screenshoter],
      manager: [SnapDiff::SnapManager, diff, :manager]
    }.each do |name, (expected, mod, mattr)|
      check_both(name, expected, mod, mattr)
    end

    # 3) Capybara-coupled wait is read at CALL time (live), not frozen.
    Capybara.default_max_wait_time = 42.5
    check("default_options[:wait] follows Capybara.default_max_wait_time set after require",
      42.5, Capybara::Screenshot::Diff.default_options[:wait])
  RUBY

  # Probe B: ENV["CI"] present (non-empty) BEFORE the require flips the
  # fail_if_new default on -- and unsetting it after the require does not
  # flip it back (frozen at require time).
  CI_SET_SCRIPT = CHECK_HELPER + <<~RUBY
    require ENV.fetch("PROBE_ENTRY")
    ENV.delete("CI")
    check_both(:fail_if_new, true, Capybara::Screenshot::Diff, :fail_if_new)
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
    check_both(:root, Pathname("/fake-rails-root-at-require"), Capybara::Screenshot, :root)
  RUBY

  ENTRY_POINTS.each do |entry|
    test "#{entry}: defaults snapshot matches through both surfaces; ENV/pwd frozen at require, wait live" do
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
