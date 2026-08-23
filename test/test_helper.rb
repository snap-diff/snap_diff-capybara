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

require "snap_diff/integrations/minitest"

# The deprecation machinery this file used to configure -- the migration
# notice, the 2.1 removal warnings, and the `Warning` guard that raised on
# any `[snap_diff deprecation]` line -- went with 2.1. There is no channel
# left to suppress or to police: a legacy require now fails loudly by
# itself, and the two static gates (core_tree_has_no_legacy_deps_test,
# canonical_suite_has_no_legacy_refs_test) catch names that only appear in
# text.
#
# The DriverCoverage banner/abort went the same way. It guarded against a
# SILENT fallback to chunky_png when libvips was missing; with one backend a
# missing libvips is a `require "vips"` LoadError at boot, not a quiet
# downgrade.

require "support/stub_test_methods"
require "support/setup_capybara_drivers"
require "support/test_helpers"

SnapDiff.config.root = Rails.root
SnapDiff.config.save_path = "./doc/screenshots"

class ActiveSupport::TestCase
  include TestHelpers::Assertions
  include TestHelpers::DriverSetup
  include TestHelpers::TestData

  # Set up fixtures and test helpers
  self.file_fixture_path = Pathname.new(File.expand_path("fixtures", __dir__))

  # Snapshot ALL global config state before each test, restore after.
  # Prevents one test from poisoning another via leaked config changes.
  # Since ADR-008 step 1 the single storage is the SnapDiff.config instance
  # (the legacy Capybara::Screenshot / ::Diff accessors delegate to it), so
  # snapshotting its instance variables covers both surfaces.
  setup do
    config = SnapDiff.config
    @_global_snapshots = config.instance_variables.map { |iv|
      [iv, config.instance_variable_get(iv)]
    }
    @_orig_cwd = Dir.pwd
    @_orig_capybara_app = Capybara.app

    SnapDiff.config.fail_if_new = false
    SnapDiff.config.blur_active_element = false
    SnapDiff.config.hide_caret = false
    SnapDiff.config.disable_animations = false
  end

  teardown do
    # Restore all global config state
    @_global_snapshots&.each do |iv, val|
      SnapDiff.config.instance_variable_set(iv, val)
    end
    Dir.chdir(@_orig_cwd) if @_orig_cwd && Dir.pwd != @_orig_cwd
    Capybara.app = @_orig_capybara_app if @_orig_capybara_app
    SnapDiff::SnapManager.cleanup! unless persist_comparisons?
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
    assert_predicate(SnapDiff::Comparison.new(image_path, expected_image_path), :quick_equal?)
  end

  def assert_stored_screenshot(filename)
    assert_includes(
      SnapDiff::SnapManager.screenshots,
      filename,
      "Screenshot #{filename} not found in #{SnapDiff::SnapManager.instance.root}"
    )
  end
end
