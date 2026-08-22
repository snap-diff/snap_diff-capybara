# frozen_string_literal: true

# The MAPPING below references the legacy modules, so they must be loaded
# first. Requires config_legacy directly (a leaf, see its own header
# comment), not the capybara_screenshot_diff umbrella -- config.rb is
# required by both snap_diff.rb and (indirectly) capybara_screenshot_diff.rb,
# and neither of those may lead back here.
require "capybara/screenshot/diff/config_legacy"

module SnapDiff
  # Flat, additive consolidation of every existing
  # +Capybara::Screenshot+ / +Capybara::Screenshot::Diff+ +mattr_accessor+
  # setting behind one object: <tt>SnapDiff.config.<em>attr</em></tt>.
  #
  # Storage ownership: the OLD mattr_accessors remain the single source of
  # truth. Config holds no state of its own -- every reader/writer defined
  # from {MAPPING} simply forwards to the existing accessor. This is
  # deliberate, not just simplest: several of those accessors carry default
  # logic with observable timing (+fail_if_new+ derives its default from
  # +ENV["CI"]+, +root+ falls back to +Rails.root+) that Rails' +mattr_accessor+
  # evaluates once, at class-body-eval time, when +capybara_screenshot_diff.rb+
  # first loads. Re-implementing that logic here -- even faithfully -- would
  # mean evaluating it again, at a different moment (Config#new time), which
  # is exactly the kind of "when defaults are evaluated" divergence the v2
  # consolidation must not introduce. Delegating sidesteps the question
  # entirely: Config never evaluates a default, it only ever forwards to
  # whichever accessor already owns one. Bidirectional consistency (a write
  # through either the old accessor or Config is visible through the other)
  # falls out for free, because both paths read and write the exact same
  # class-variable-backed storage.
  class Config
    # config attr name => [owning module, mattr_accessor name].
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

    MAPPING.each do |name, (mod, mattr)|
      define_method(name) { mod.public_send(mattr) }
      define_method(:"#{name}=") { |value| mod.public_send(:"#{mattr}=", value) }
    end
  end
end
