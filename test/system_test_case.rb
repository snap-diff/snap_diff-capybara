# frozen_string_literal: true

require "test_helper"

require "support/setup_capybara_drivers"

class SystemTestCase < ActionDispatch::IntegrationTest
  BROWSERS = {cuprite: "chrome", selenium_headless: "firefox", selenium_chrome_headless: "chrome"}

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
    Capybara::Screenshot.window_size = [800, 600]

    # NOTE: For small screenshots we should have pixel perfect comparisons
    @orig_tolerance = Capybara::Screenshot::Diff.tolerance
    Capybara::Screenshot::Diff.tolerance = nil
  end

  include Capybara::Screenshot::Diff

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
      Vips.vips_cache_set_max(1000)
    end
  end

  private

  def rollback_comparison_runtime_files(screenshot_error)
    screenshot_name, comparison = screenshot_error[1], screenshot_error[2]
    debug_diffs_save_path = Pathname.new(Capybara.save_path) / "screenshots-diffs" / name

    save_annotations_for_debug(comparison, debug_diffs_save_path)

    restore_git_revision(screenshot_name, comparison.new_file_name)
    comparison.clean_tmp_files
  end

  def save_annotations_for_debug(comparison, debug_diffs_save_path)
    FileUtils.mkdir_p(debug_diffs_save_path)

    if File.exist?(comparison.new_file_name)
      FileUtils.mv(comparison.new_file_name, debug_diffs_save_path)
    end

    if File.exist?(comparison.annotated_old_file_name)
      FileUtils.mv(comparison.annotated_old_file_name, debug_diffs_save_path)
    end

    if File.exist?(comparison.annotated_new_file_name)
      FileUtils.mv(comparison.annotated_new_file_name, debug_diffs_save_path)
    end
  end

  def validate_screenshots
    Array(@test_screenshots&.select { |screenshot_assert| screenshot_assert.last.different? })
  end
end
