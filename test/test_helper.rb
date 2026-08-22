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

# Many tests deliberately exercise the old (pre-v2) constant names, which
# warn once per constant per process since v2 step 6. Silence them globally
# so suite output stays clean; the deprecation behavior itself is pinned by
# unit/legacy_namespace_deprecation_test.rb (which flips this flag off per
# test) and by its unsilenced subprocess probes.
SnapDiff.silence_deprecations = true

require "support/stub_test_methods"
require "support/setup_capybara_drivers"
require "support/test_helpers"
require "support/driver_coverage"

Capybara::Screenshot.root = Rails.root
Capybara::Screenshot.save_path = "./doc/screenshots"

puts CapybaraScreenshotDiff::DriverCoverage.banner(Capybara::Screenshot::Diff::AVAILABLE_DRIVERS)

missing_drivers = CapybaraScreenshotDiff::DriverCoverage.missing_for_ci(
  Capybara::Screenshot::Diff::AVAILABLE_DRIVERS,
  ci: ENV["CI"],
  exclude: ENV["CI_EXPECTED_DRIVERS_EXCLUDE"]&.split(",")&.map(&:to_sym)
)
abort("[capybara-screenshot-diff] CI is missing expected driver(s): #{missing_drivers.join(", ")}") if missing_drivers.any?

class ActiveSupport::TestCase
  include TestHelpers::Assertions
  include TestHelpers::DriverSetup
  include TestHelpers::TestData

  # Set up fixtures and test helpers
  self.file_fixture_path = Pathname.new(File.expand_path("fixtures", __dir__))

  # Snapshot ALL global state before each test, restore after.
  # Prevents one test from poisoning another via leaked mattr_accessor changes.
  GLOBAL_STATE_MODULES = [
    Capybara::Screenshot,
    Capybara::Screenshot::Diff
  ].freeze

  setup do
    @_global_snapshots = GLOBAL_STATE_MODULES.map { |mod|
      attrs = mod.class_variables.map { |cv| [cv, mod.class_variable_get(cv)] }
      [mod, attrs]
    }.to_h
    @_orig_cwd = Dir.pwd
    @_orig_capybara_app = Capybara.app

    Capybara::Screenshot::Diff.fail_if_new = false
    Capybara::Screenshot.blur_active_element = false
    Capybara::Screenshot.hide_caret = false
    Capybara::Screenshot.disable_animations = false
  end

  teardown do
    # Restore all global state
    @_global_snapshots&.each do |mod, attrs|
      attrs.each { |cv, val| mod.class_variable_set(cv, val) }
    end
    Dir.chdir(@_orig_cwd) if @_orig_cwd && Dir.pwd != @_orig_cwd
    Capybara.app = @_orig_capybara_app if @_orig_capybara_app
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
