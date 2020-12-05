require "test_helper"

require "webdrivers/chromedriver"
Webdrivers::Chromedriver.update

class SystemTestCase < ActionDispatch::IntegrationTest
  setup do
    Capybara.current_driver = :selenium_chrome_headless
    # TODO: Allow to test with different drivers by ENV
    # Capybara.current_driver = :selenium_chrome
    # Capybara.current_driver = :selenium

    # TODO: Reset original settings to previous values
    @orig_root = Capybara::Screenshot.root
    Capybara::Screenshot.root = "."
    @orig_save_path = Capybara::Screenshot.save_path
    Capybara::Screenshot.save_path = "test/fixtures/app/doc/screenshots"
    Capybara::Screenshot.enabled = true
    Capybara::Screenshot::Diff.enabled = true
    Capybara::Screenshot::Diff.driver = :vips

    # TODO: Makes configurations copying and restoring much easier

    @orig_add_os_path = Capybara::Screenshot.add_os_path
    Capybara::Screenshot.add_os_path = true
    @orig_add_driver_path = Capybara::Screenshot.add_driver_path
    Capybara::Screenshot.add_driver_path = true
    # NOTE: Only works before `include Capybara::Screenshot::Diff` line
    @orig_window_size = Capybara::Screenshot.window_size
    Capybara::Screenshot.window_size = [800, 600]

    # NOTE: For small screenshots we should have pixel perfect comparisons
    @orig_tolerance = Capybara::Screenshot::Diff.tolerance
    Capybara::Screenshot::Diff.tolerance = nil
  end

  include Capybara::Screenshot::Diff

  teardown do
    if @test_screenshots
      @test_screenshots.each(&method(:rollback_comparison_runtime_files))
      # NOTE: We clear tracked different errors in order to not raise error
      @test_screenshots.clear
    end

    # Restore to previous values
    Capybara::Screenshot.root = @orig_root
    Capybara::Screenshot.save_path = @orig_save_path
    Capybara::Screenshot.add_os_path = @orig_add_os_path
    Capybara::Screenshot.add_driver_path = @orig_add_driver_path
    Capybara::Screenshot.window_size = @orig_window_size
    Capybara::Screenshot::Diff.tolerance = @orig_tolerance
    Capybara.current_driver = Capybara.default_driver
  end

  private

  def rollback_comparison_runtime_files(screenshot_error)
    screenshot_name, comparison = screenshot_error[1], screenshot_error[2]
    restore_git_revision(screenshot_name, comparison.new_file_name)
    comparison.clean_tmp_files
  end
end
