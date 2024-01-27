# frozen_string_literal: true

require "system_test_case"

module Capybara::Screenshot
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

      screenshot("index-cropped", crop: "form", color_distance_limit: 40)

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
      screenshot("index_with_skip_area_as_array_of_css", skip_area: ["form"])
      screenshot("index_with_skip_area_as_array_of_css_and_p", skip_area: [[90, 950, 180, 1000], "form"])

      assert_no_screenshot_errors
    end

    test "skip_area converts coordinates to be relative to cropped region" do
      visit "/index.html"

      fill_in "First Field:", with: "New Change"
      fill_in "Second Field:", with: "New Change"

      screenshot("index-cropped", skip_area: "#first-field", crop: "form")

      assert_not_predicate @test_screenshots, :empty?, "differences have not been found when they should have been"
      assert @test_screenshots.last.last.different?, "should provide comparison object in the error"
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

      screenshot("index-cropped", skip_area: "input", crop: "form")

      assert_no_screenshot_errors
    end

    test "bounds_for_css for multiple elements returns all areas" do
      visit "/"

      label_bounds = BrowserHelpers.bounds_for_css("label")

      assert_equal 2, label_bounds.size
    end

    test "rect_for for multiple elements returns first visible element" do
      visit "/index.html"

      label_bound = rect_for("label")

      assert_equal 4, label_bound.size
    end

    test "animated example" do
      optional_test

      visit "/index-with-anim.html"

      assert_raises RuntimeError, "Could not get stable screenshot within 1s:" do
        # We need to run several times,
        # because quick_equal could produce incorrect result,
        # because of the same size screenshots
        10.times do
          screenshot "index-with-anim", stability_time_limit: 0.33, wait: 0.5
        end
      end
    ensure
      FileUtils.rm_rf(Capybara::Screenshot.screenshot_area_abs / "index-with-anim.png")
    end

    def test_await_all_images_are_loaded
      visit "/index.html"
      assert_raises Minitest::Assertion do
        BrowserHelpers.stub(:pending_image_to_load, "http://127.0.0.1:62815/image.png") do
          screenshot :index
        end
      end
      assert_no_screenshot_errors
    end

    private

    def rect_for(css_selector)
      BrowserHelpers.all_visible_regions_for(css_selector).first
    end

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
  end
end
