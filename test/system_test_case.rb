# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff/minitest"

require "support/setup_capybara_drivers"

class SystemTestCase < ActiveSupport::TestCase
  setup do
    Capybara.current_driver = Capybara.javascript_driver
    browser = BROWSERS.fetch(Capybara.current_driver, "chrome")

    Capybara.page.current_window.resize_to(*SCREEN_SIZE)

    Capybara::Screenshot.enabled = true
    Capybara::Screenshot::Diff.enabled = true

    # TODO: Reset original settings to previous values
    @orig_root = Capybara::Screenshot.root
    Capybara::Screenshot.root = "."
    @orig_save_path = Capybara::Screenshot.save_path
    Capybara::Screenshot.save_path = "test/fixtures/app/doc/screenshots/#{browser}"
    Capybara::Screenshot::Diff.driver = ENV.fetch("SCREENSHOT_DRIVER", "chunky_png").to_sym

    # TODO: Makes configurations copying and restoring much easier

    @orig_add_os_path = Capybara::Screenshot.add_os_path
    Capybara::Screenshot.add_os_path = true
    @orig_add_driver_path = Capybara::Screenshot.add_driver_path
    Capybara::Screenshot.add_driver_path = false
    # NOTE: Only works before `include Capybara::Screenshot::Diff` line
    @orig_window_size = Capybara::Screenshot.window_size
    Capybara::Screenshot.window_size = SCREEN_SIZE

    # NOTE: For small screenshots we should have pixel perfect comparisons
    @orig_tolerance = Capybara::Screenshot::Diff.tolerance
    Capybara::Screenshot::Diff.tolerance = nil
  end

  include Capybara::Screenshot::Diff
  include CapybaraScreenshotDiff::Minitest::Assertions

  teardown do
    # Restore to previous values
    Capybara::Screenshot.root = @orig_root
    Capybara::Screenshot.save_path = @orig_save_path
    Capybara::Screenshot.add_os_path = @orig_add_os_path
    Capybara::Screenshot.add_driver_path = @orig_add_driver_path
    Capybara::Screenshot.window_size = @orig_window_size
    Capybara::Screenshot::Diff.tolerance = @orig_tolerance
    Capybara.current_driver = Capybara.default_driver

    if Capybara::Screenshot::Diff.driver == :vips
      Vips.cache_set_max(0)
      Vips.cache_set_max(1000)
    end
  end

  private

  def rollback_comparison_runtime_files((_, _, comparison))
    save_annotations_for_debug(comparison)

    screenshot_path = comparison.image_path
    Vcs.restore_git_revision(screenshot_path, screenshot_path)

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

  def run_screenshots_validation
    return [] unless @test_screenshots

    @test_screenshots.select { |screenshot_assert| screenshot_assert.last.different? }
  end
end
