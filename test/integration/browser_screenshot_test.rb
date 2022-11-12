# frozen_string_literal: true

require "system_test_case"

class BrowserScreenshotTest < SystemTestCase
  setup do
    Capybara::Screenshot.blur_active_element = true
  end

  teardown do
    Capybara::Screenshot.blur_active_element = nil

    if @test_screenshots
      @test_screenshots.each(&method(:rollback_comparison_runtime_files))
      # NOTE: We clear tracked different errors in order to not raise error
      @test_screenshots.clear
    end
  end

  def test_screenshot_without_changes
    visit "/"
    screenshot "index"
  end

  def test_screenshot_with_changes
    visit "/"

    fill_in "First Field:", with: "Some changes in the field"

    assert screenshot("index")

    assert_screenshot_error_for("index")
  end

  def test_window_size_should_resize_browser_window_in_setup
    assert_equal [800, 600], window_size
  end

  def test_screenshot_with_hide_caret_enabled
    Capybara::Screenshot.hide_caret = true

    visit "/"
    fill_in "First Field:", with: "Test Input With Hide Caret"
    screenshot "index-hide_caret-enabled"
  ensure
    Capybara::Screenshot.hide_caret = nil
  end

  def test_screenshot_with_hide_caret_disabled
    Capybara::Screenshot.hide_caret = false

    visit "/"
    fill_in "First Field:", with: "Test Input Without Hide Caret"

    # Hide caret is flaky issue, let's give more tries to take stable screenshot
    screenshot "index-hide_caret-disabled", wait: Capybara.default_max_wait_time * 5
  ensure
    Capybara::Screenshot.hide_caret = nil
  end

  def test_screenshot_with_blur_active_element_enabled
    Capybara::Screenshot.blur_active_element = true

    visit "/"
    fill_in "First Field:", with: "Test Input With Hide Caret"
    screenshot "index-blur_active_element-enabled"
  ensure
    Capybara::Screenshot.blur_active_element = nil
  end

  def test_screenshot_with_blur_active_element_disabled
    Capybara::Screenshot.blur_active_element = false

    visit "/"
    fill_in "First Field:", with: "Test Input Without Hide Caret"
    screenshot "index-blur_active_element-disabled"
  ensure
    Capybara::Screenshot.blur_active_element = nil
  end

  def test_screenshot_selected_element
    visit "/"

    screenshot "cropped_screenshot", crop: [0, 100, 100, 200]
  end

  test "skip_area accepts passing multiple coordinates as one array" do
    visit "/"

    fill_in "First Field:", with: "Changed"
    fill_in "Second Field:", with: "Changed"

    screenshot("index", skip_area: [8, 100, 218, 140, 8, 140, 218, 180])

    assert_no_screenshot_errors
  end

  test "compare crops only when other part is not working" do
    visit "/index-without-img.html"

    screenshot("index-cropped", crop: rect_for("form"), color_distance_limit: 40)

    assert_no_screenshot_errors
  end

  test "crop accepts css selector" do
    visit "/index-without-img.html"

    screenshot("index-cropped", crop: "form")

    assert_no_screenshot_errors
  end

  test "skip_area accepts css selector" do
    visit "/"

    fill_in "First Field:", with: "Changed"
    fill_in "Second Field:", with: "Changed"

    screenshot("index", skip_area: "form")

    assert_no_screenshot_errors
  end

  test "skip_area converts coordinates to be relative to cropped region" do
    visit "/index.html"
    fill_in "First Field:", with: "New Change"
    fill_in "Second Field:", with: "New Change"

    skip_left_top_square = [0, 0, 170, 110] # skip only first field, but the second should not be skipped
    screenshot("index-cropped", skip_area: skip_left_top_square, crop: rect_for("form"))

    assert @test_screenshots.last.last.different?, "second field should not be skipped"
  end

  test "skip_area by css selectors" do
    visit "/"

    fill_in "First Field:", with: "Test Input With Hide Caret"

    screenshot("index", skip_area: "form")

    assert_no_screenshot_errors
  end

  test "crop and skip_area by css selectors" do
    visit "/index-without-img.html"

    fill_in "First Field:", with: "Test Input With Hide Caret"

    screenshot("index-cropped", skip_area: "input", crop: rect_for("form"))

    assert_no_screenshot_errors
  end

  test "bounds_for_css for multiple elements returns all areas" do
    visit "/"

    label_bounds = bounds_for_css("label")

    assert_equal 2, label_bounds.size
  end

  test "rect_for for multiple elements returns first visible element" do
    visit "/index.html"

    label_bound = rect_for("label")

    assert_equal 4, label_bound.size
  end

  private

  def window_size
    if page.driver.respond_to?(:window_size)
      return page.driver.window_size(page.driver.current_window_handle)
    end

    page.driver.browser.manage.window.size.to_a
  end

  def assert_screenshot_error_for(screenshot_name)
    validate_screenshots

    assert_equal 1, @test_screenshots&.length, "expecting to have just one difference"
    assert_equal screenshot_name, @test_screenshots[0][1], "index screenshot should have difference for changed page"
  end

  def assert_no_screenshot_errors
    screenshots = validate_screenshots

    error_messages = screenshots.map { |screenshot_error| screenshot_error.last.error_message }

    assert(
      screenshots.empty?,
      "expecting not to have any difference. But got next: #{error_messages.join("; ")}"
    )
  end

  # TODO: Add test for stability to await while image are loading
end
