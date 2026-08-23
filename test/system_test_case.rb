# frozen_string_literal: true

require "test_helper"
require "snap_diff/integrations/minitest"
require "snap_diff/reporters/html"

require "support/setup_capybara_drivers"

class SystemTestCase < ActiveSupport::TestCase
  setup do
    Capybara.current_driver = Capybara.javascript_driver
    Capybara.page.current_window.resize_to(*SCREEN_SIZE)

    SnapDiff.config.screenshot_enabled = true
    SnapDiff.config.enabled = true

    # TODO: Reset original settings to previous values
    @orig_root = SnapDiff.config.root
    SnapDiff.config.root = Rails.root / "../test/fixtures/app"

    @orig_save_path = SnapDiff.config.save_path
    SnapDiff.config.save_path = "./doc/screenshots"

    # `SnapDiff.config.driver = ENV.fetch("SCREENSHOT_DRIVER", ...)` is gone
    # with the setting: 2.1 made libvips the only backend, so there is nothing
    # for the env var to select.

    # TODO: Makes configurations copying and restoring much easier

    @orig_add_os_path = SnapDiff.config.add_os_path
    SnapDiff.config.add_os_path = true
    @orig_add_driver_path = SnapDiff.config.add_driver_path
    SnapDiff.config.add_driver_path = true
    # NOTE: Only works before the `include SnapDiff::DSL` line
    @orig_window_size = SnapDiff.config.window_size
    SnapDiff.config.window_size = SCREEN_SIZE

    # NOTE: For small screenshots we should have pixel perfect comparisons
    @orig_tolerance = SnapDiff.config.tolerance
    SnapDiff.config.tolerance = nil
  end

  include SnapDiff::DSL
  include SnapDiff::Minitest::Assertions

  teardown do
    # Restore to previous values
    SnapDiff.config.root = @orig_root
    SnapDiff.config.save_path = @orig_save_path
    SnapDiff.config.add_os_path = @orig_add_os_path
    SnapDiff.config.add_driver_path = @orig_add_driver_path
    SnapDiff.config.window_size = @orig_window_size
    SnapDiff.config.tolerance = @orig_tolerance
    Capybara.current_driver = Capybara.default_driver

    # The vips cache flush that used to live here (cache_set_max 0 then 1000)
    # papered over libvips serving a stale image when a screenshot path was
    # rewritten within the same second. VipsDriver#from_file now passes
    # `revalidate: true`, so the workaround is gone -- see the regression test
    # in test/unit/drivers/vips_driver_test.rb.
  end

  private

  def rollback_comparison_runtime_files(screenshot_assert)
    comparison = screenshot_assert.is_a?(SnapDiff::ScreenshotAssertion) ? screenshot_assert.compare : screenshot_assert[2]
    return unless comparison

    save_annotations_for_debug(comparison)

    screenshot_path = comparison.image_path
    SnapDiff::Vcs.checkout_vcs(SnapDiff.config.root, screenshot_path, screenshot_path)

    if comparison.difference
      comparison.reporter.clean_tmp_files
    end
  end

  def save_annotations_for_debug(comparison)
    debug_diffs_save_path = Pathname.new(Capybara.save_path) / "screenshots-diffs" / name
    debug_diffs_save_path.mkpath unless debug_diffs_save_path.exist?

    if File.exist?(comparison.image_path)
      FileUtils.cp(comparison.image_path, debug_diffs_save_path)
    end

    if comparison.reporter.annotated_base_image_path.exist?
      FileUtils.mv(comparison.reporter.annotated_base_image_path, debug_diffs_save_path, force: true)
    end

    if comparison.reporter.annotated_image_path.exist?
      FileUtils.mv(comparison.reporter.annotated_image_path, debug_diffs_save_path, force: true)
    end
  end
end
