# frozen_string_literal: true

require "test_helper"
# The shared harness loads canonical entry points only, so a legacy-surface
# test pulls in the v1 entry itself -- the require goes with the file in 3.0.
require "capybara_screenshot_diff"

# ADR-008 step 2: the error classes live in SnapDiff (snap_diff/errors);
# the old CapybaraScreenshotDiff names are EAGER same-object aliases --
# deliberately not const_missing shims -- so adopter rescue clauses and
# defined?/const_defined? feature detection keep working unchanged.
# Note the absence of any deprecation-silencing here: eager aliases never
# warn, and the suite-wide guard in test_helper raises on unexpected
# warnings, so these tests double as proof the aliases stay warning-free.
#
# LEGACY SURFACE (test/legacy/, see the Rakefile): deleted with lib/capybara*
# in 3.0. The hierarchy assertions that outlive the aliases moved to
# test/unit/errors_test.rb.
class ErrorsAliasTest < ActiveSupport::TestCase
  # old constant path => new constant path
  MAPPING = {
    "CapybaraScreenshotDiff::CapybaraScreenshotDiffError" => "SnapDiff::Error",
    "CapybaraScreenshotDiff::ExpectationNotMet" => "SnapDiff::ExpectationNotMet",
    "CapybaraScreenshotDiff::UnstableImage" => "SnapDiff::UnstableImage",
    "CapybaraScreenshotDiff::WindowSizeMismatchError" => "SnapDiff::WindowSizeMismatchError"
  }.freeze

  MAPPING.each do |old_name, new_name|
    test "#{old_name} is the same object as #{new_name}" do
      assert_same Object.const_get(new_name), Object.const_get(old_name),
        "#{old_name} must alias the exact #{new_name} object"
    end

    # The regression the eager choice prevents: const_defined? (and
    # defined?) never trigger const_missing, so a lazy shim would make
    # feature detection by the old name silently return false.
    test "#{old_name} is visible to const_defined? without const_missing" do
      mod, leaf = old_name.rpartition("::").values_at(0, 2)
      assert Object.const_get(mod).const_defined?(leaf, false),
        "#{leaf} must be an eagerly-defined constant on #{mod}"
      assert defined?(CapybaraScreenshotDiff), "sanity: old namespace present"
    end
  end

  test "rescue by old name catches an error raised under the new name" do
    caught = nil
    begin
      raise SnapDiff::ExpectationNotMet.new("probe", caller)
    rescue CapybaraScreenshotDiff::ExpectationNotMet => e
      caught = e
    end
    assert_equal "probe", caught.message
  end
end
