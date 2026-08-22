# frozen_string_literal: true

require "pathname"

# This file is the LEAF of the config require graph (ADR-008 step 1):
# config_legacy.rb requires it, so it must never require config_legacy nor
# anything that leads back to either entry point. The MAPPING below needs
# the legacy module constants to exist at class-body eval time, so the empty
# skeleton is predefined here (same technique as legacy_shims.rb);
# config_legacy.rb reopens these modules and installs the delegating
# accessors from MAPPING.
module Capybara
  module Screenshot
    module Diff
    end
  end
end

# Referenced by Config#initialize (screenshoter/manager defaults), which
# runs at the eager Config.new at the bottom of this file, so they must be
# real, already-loaded classes first. Neither requires back here.
require "snap_diff/screenshoter"
require "snap_diff/snap_manager"

module SnapDiff
  # Flat consolidation of every legacy +Capybara::Screenshot+ /
  # +Capybara::Screenshot::Diff+ setting behind one object:
  # <tt>SnapDiff.config.<em>attr</em></tt>.
  #
  # Storage ownership (ADR-008 step 1, inverted from the original v2
  # consolidation): Config IS the single storage. The legacy accessors on
  # +Capybara::Screenshot+ / +Capybara::Screenshot::Diff+ are thin
  # delegators installed by config_legacy.rb from {MAPPING} -- one storage,
  # two views, so a write through either surface is visible through the
  # other structurally, not by synchronization.
  #
  # Default timing contract (pinned by config_default_timing_test.rb):
  # every default below is evaluated ONCE, in #initialize, which runs at
  # require time of this file (the eager +Config.new+ at the bottom) -- the
  # same load moment the old +mattr_accessor+ default blocks evaluated at.
  # In particular +fail_if_new+ (from <tt>ENV["CI"]</tt>) and +root+ (from
  # +Rails.root+ / pwd) must never become lazy read-time defaults, memoized
  # or not. The one deliberately LIVE value, +default_options[:wait]+, is
  # not storage at all: it stays a method-body read of
  # +Capybara.default_max_wait_time+ in +#default_options+.
  class Config
    # config attr name => [legacy module, legacy accessor name].
    #
    # The two names differ only for +screenshot_enabled+:
    # +Capybara::Screenshot.enabled+ and +Capybara::Screenshot::Diff.enabled+
    # are independent settings (see +Capybara::Screenshot.active?+, which
    # reads both) that happen to share a bare name in their own modules. A
    # flat Config can't expose two attributes both called +enabled+, so the
    # Screenshot-side one is renamed here; Diff's keeps the bare +enabled+
    # name since it's the one most existing configuration touches directly.
    MAPPING = {
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

    attr_accessor(*(MAPPING.keys - [:root]))
    attr_reader :root

    def initialize
      # Every mapped setting gets its ivar up front (nil-defaulted ones
      # included) so the full set always exists -- test_helper's per-test
      # isolation snapshots/restores config by instance variable, and an
      # ivar that only appears on first write would escape that snapshot
      # and leak between tests.
      MAPPING.each_key { |key| instance_variable_set(:"@#{key}", nil) }
      # Capybara::Screenshot side.
      @blur_active_element = true
      @hide_caret = true
      # Raw Rails.root (no coercion), matching the old mattr_reader default;
      # only the writer below coerces.
      @root = (defined?(Rails) && defined?(Rails.root) && Rails.root) || Pathname(".").expand_path
      @save_path = "doc/screenshots"
      @screenshot_format = "png"
      @capybara_screenshot_options = {}
      # Capybara::Screenshot::Diff side.
      @delayed = true
      @fail_if_new = !ENV["CI"].nil? && !ENV["CI"].empty?
      @pending_if_new = false
      @fail_on_difference = true
      @enabled = true
      @driver = :auto
      @screenshoter = SnapDiff::Screenshoter
      @manager = SnapDiff::SnapManager
    end

    def root=(path)
      @root = Pathname(path).expand_path
    end

    # --- Derived config (ADR-008 step 7b) -------------------------------
    # Read-only values computed from the storage above. They used to live
    # on the legacy modules; those now one-line forward here.

    # ex +Capybara::Screenshot.active?+. The two +enabled+ settings are
    # independent (see {MAPPING}): the Screenshot-side one wins whenever it
    # was set at all, and only a nil there falls through to the Diff-side
    # one.
    def active?
      screenshot_enabled || (screenshot_enabled.nil? && enabled)
    end

    # ex +Capybara::Screenshot.screenshot_area+: the save_path, optionally
    # segmented per OS and per Capybara driver.
    def screenshot_area
      parts = [save_path]
      parts << Os.name if add_os_path
      parts << Capybara.current_driver.to_s if add_driver_path
      File.join(*parts)
    end

    # ex +Capybara::Screenshot.screenshot_area_abs+.
    def screenshot_area_abs
      root / screenshot_area
    end

    # ex +Capybara::Screenshot::Diff.default_options+: the capture/compare
    # defaults handed to {SnapDiff::Comparison}. Carries the one literal
    # that is not a stored setting -- the vips tolerance floor.
    def default_options
      {
        area_size_limit: area_size_limit,
        color_distance_limit: color_distance_limit,
        driver: driver,
        screenshot_format: screenshot_format,
        capybara_screenshot_options: capybara_screenshot_options,
        perceptual_threshold: perceptual_threshold,
        shift_distance_limit: shift_distance_limit,
        skip_area: skip_area,
        stability_time_limit: stability_time_limit,
        tolerance: tolerance || ((driver == :vips) ? 0.001 : nil),
        # Deliberately LIVE (pinned by config_default_timing_test.rb):
        # read at call time, never frozen into storage.
        wait: Capybara.default_max_wait_time
      }
    end
  end

  # Instantiated eagerly so the require-time defaults above are evaluated
  # NOW, at load, not at the first SnapDiff.config call.
  @config = Config.new

  # The single consolidated settings object -- and the single storage.
  # See {SnapDiff::Config}.
  def self.config
    @config
  end

  # Installs the old mattr_accessor surface onto the legacy modules,
  # delegating to the single storage above. mattr_accessor used to define
  # both singleton and instance accessors (the instance ones are what
  # `include Capybara::Screenshot::Diff` picks up), so both are installed.
  # root keeps its historical asymmetry -- readable everywhere, writable
  # only at module level (it was mattr_reader plus a custom module-level
  # writer) -- with the Pathname coercion living in Config#root=.
  #
  # Generated here rather than in config_legacy.rb (ADR-008 step 7b) for
  # the same reason legacy_shims.rb generates the legacy constants here:
  # the generator is code, and the v1 trees must stay alias-only so 3.0 is
  # a `git rm`. Same technique, same side of the fence.
  Config::MAPPING.each do |name, (mod, mattr)|
    [mod, mod.singleton_class].each do |target|
      target.define_method(mattr) { SnapDiff.config.public_send(name) }
      next if name == :root && target == mod

      target.define_method(:"#{mattr}=") { |value| SnapDiff.config.public_send(:"#{name}=", value) }
    end
  end
end
