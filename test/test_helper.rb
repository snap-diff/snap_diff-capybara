# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "test_frameworks" do
    enable_coverage :branch
    minimum_coverage line: 90, branch: 68

    add_filter("gemfiles")
    add_filter("test")
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "pathname"
TEST_IMAGES_DIR = Pathname.new(File.expand_path("images", __dir__))

require "support/setup_rails_app"
require "minitest/autorun"

require "capybara/minitest"
require "support/setup_capybara"

require "capybara_screenshot_diff/minitest"

require "support/stub_test_methods"
require "support/setup_capybara_drivers"

class ActiveSupport::TestCase
  self.file_fixture_path = Pathname.new(File.expand_path("fixtures", __dir__))

  teardown do
    FileUtils.rm_rf Dir[Capybara::Screenshot.root / "*"]
  end

  def optional_test
    unless ENV["DISABLE_SKIP_TESTS"]
      skip "This is optional test! To enable need to provide DISABLE_SKIP_TESTS=1"
    end
  end

  def assert_same_images(expected_image_name, image_path)
    expected_image_path = file_fixture("files/comparisons/#{expected_image_name}")
    assert_predicate(Capybara::Screenshot::Diff::ImageCompare.new(image_path, expected_image_path), :quick_equal?)
  end

  def assert_stored_screenshot(filename)
    screenshots = Capybara::Screenshot.screenshot_area_abs.children.map { |f| f.basename.to_s }

    assert_includes(
      screenshots,
      filename,
      "Screenshot #{filename} not found in #{Capybara::Screenshot.screenshot_area_abs}"
    )
  end
end
