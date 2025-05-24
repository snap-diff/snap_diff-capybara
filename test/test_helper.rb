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
TEST_IMAGES_DIR = Pathname.new(File.expand_path("fixtures/images", __dir__))

require "support/setup_rails_app"
require "minitest/autorun"

require "capybara/minitest"
require "support/setup_capybara"

require "capybara_screenshot_diff/minitest"

require "support/stub_test_methods"
require "support/setup_capybara_drivers"
require "support/test_helpers"

Capybara::Screenshot.root = Rails.root
Capybara::Screenshot.save_path = "./doc/screenshots"

class ActiveSupport::TestCase
  include TestHelpers::Assertions
  include TestHelpers::DriverSetup
  include TestHelpers::TestData

  # Set up fixtures and test helpers
  self.file_fixture_path = Pathname.new(File.expand_path("fixtures", __dir__))

  parallelize

  parallelize_setup do |i|
    Rails.root = Pathname.new(File.expand_path("../tmp", __dir__)) / i.to_s
    Capybara::Screenshot.root = Rails.root
    FileUtils.mkdir_p(Capybara::Screenshot.root)
  end

  teardown do
    CapybaraScreenshotDiff::SnapManager.cleanup! unless persist_comparisons?
  end

  def persist_comparisons?
    ENV["DEBUG"] || ENV["DISABLE_ROLLBACK_COMPARISON_RUNTIME_FILES"] || ENV["RECORD_SCREENSHOTS"]
  end

  def optional_test
    unless ENV["DISABLE_SKIP_TESTS"]
      skip "This is optional test! To enable provide DISABLE_SKIP_TESTS=1"
    end
  end

  private

  def fixture_image_path_from(original_new_image, ext = "png")
    file_fixture("images/#{original_new_image}.#{ext}")
  end

  def assert_same_images(expected_image_name, image_path)
    expected_image_path = file_fixture("comparisons/#{expected_image_name}")
    assert_predicate(Capybara::Screenshot::Diff::ImageCompare.new(image_path, expected_image_path), :quick_equal?)
  end

  def assert_stored_screenshot(filename)
    assert_includes(
      CapybaraScreenshotDiff::SnapManager.screenshots,
      filename,
      "Screenshot #{filename} not found in #{CapybaraScreenshotDiff::SnapManager.instance.root}"
    )
  end
end
