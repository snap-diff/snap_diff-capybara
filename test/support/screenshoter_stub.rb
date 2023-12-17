# frozen_string_literal: true

require "capybara/screenshot/diff/screenshoter"

class Capybara::Screenshot::ScreenshoterStub < Capybara::Screenshot::Screenshoter
  def pending_image_to_load
  end

  # Stub of the Capybara's save_screenshot
  def save_screenshot(path)
    source_image = path.basename.to_path
    source_image.slice!(/\.attempt_\d+/)
    source_image.slice!(/^\d\d_/)

    FileUtils.cp(File.expand_path(source_image, TEST_IMAGES_DIR), path)

    path
  end

  def evaluate_script(*)
    # Do nothing
  end

  def prepare_page_for_screenshot(**)
    nil
  end

  def take_screenshot(screenshot_path)
    stored_path = save_screenshot(screenshot_path)

    process_screenshot(stored_path, screenshot_path)
  end
end
