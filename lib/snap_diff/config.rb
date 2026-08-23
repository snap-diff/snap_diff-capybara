# frozen_string_literal: true

require "pathname"

# This file is the LEAF of the config require graph (ADR-008 step 1): it must
# never require anything that leads back to an entry point.

# Referenced by Config#initialize (screenshoter/manager defaults), which
# runs at the eager Config.new at the bottom of this file, so they must be
# real, already-loaded classes first. Neither requires back here.
require "snap_diff/screenshoter"
require "snap_diff/snap_manager"

module SnapDiff
  # Every setting the gem has, behind one object:
  # <tt>SnapDiff.config.<em>attr</em></tt>. Since 2.1 deleted the v1
  # namespaces this is not just the single storage but the single surface --
  # {SnapDiff.configure} is the one config entry point (ADR-008).
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
    # Every setting this object stores, in the order the two legacy holders
    # used to declare them.
    #
    # +screenshot_enabled+ is the one name that differs from its legacy
    # spelling: +Capybara::Screenshot.enabled+ and
    # +Capybara::Screenshot::Diff.enabled+ are independent settings (see
    # {#active?}, which reads both) that happened to share a bare name in
    # their own modules. A flat Config can't expose two attributes both
    # called +enabled+, so the Screenshot-side one is renamed here; Diff's
    # keeps the bare +enabled+ name since it's the one most existing
    # configuration touches directly.
    SETTINGS = %i[
      add_driver_path
      add_os_path
      blur_active_element
      screenshot_enabled
      hide_caret
      disable_animations
      root
      stability_time_limit
      window_size
      save_path
      use_lfs
      screenshot_format
      capybara_screenshot_options
      delayed
      area_size_limit
      fail_if_new
      pending_if_new
      fail_on_difference
      color_distance_limit
      enabled
      skip_area
      tolerance
      perceptual_threshold
      screenshoter
      manager
    ].freeze

    attr_accessor(*(SETTINGS - %i[root]))
    attr_reader :root

    def initialize
      # Every setting gets its ivar up front (nil-defaulted ones included)
      # so the full set always exists -- test_helper's per-test isolation
      # snapshots/restores config by instance variable, and an ivar that
      # only appears on first write would escape that snapshot and leak
      # between tests.
      SETTINGS.each { |key| instance_variable_set(:"@#{key}", nil) }
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
    # independent (see {SETTINGS}): the Screenshot-side one wins whenever it
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

    # The capture/compare defaults handed to {SnapDiff::Comparison}. Carries
    # the one literal that is not a stored setting -- the vips tolerance
    # floor, now unconditional: 2.1 made libvips the only backend, so the
    # <tt>driver == :vips</tt> guard this used to carry was always true.
    def default_options
      {
        area_size_limit: area_size_limit,
        color_distance_limit: color_distance_limit,
        screenshot_format: screenshot_format,
        capybara_screenshot_options: capybara_screenshot_options,
        perceptual_threshold: perceptual_threshold,
        skip_area: skip_area,
        stability_time_limit: stability_time_limit,
        tolerance: tolerance || 0.001,
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
end
