# frozen_string_literal: true

require "test_helper"

# ADR-008 step 2: the error classes live in SnapDiff (snap_diff/errors);
# the old CapybaraScreenshotDiff names are EAGER same-object aliases --
# deliberately not const_missing shims -- so adopter rescue clauses and
# defined?/const_defined? feature detection keep working unchanged.
# Note the absence of any deprecation-silencing here: eager aliases never
# warn, and the suite-wide guard in test_helper raises on unexpected
# warnings, so these tests double as proof the aliases stay warning-free.
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

  test "error hierarchy is preserved" do
    assert_operator SnapDiff::ExpectationNotMet, :<, SnapDiff::Error
    assert_operator SnapDiff::UnstableImage, :<, SnapDiff::Error
    assert_operator SnapDiff::Error, :<, SnapDiff::ErrorWithFilteredBacktrace
    assert_operator SnapDiff::WindowSizeMismatchError, :<, SnapDiff::ErrorWithFilteredBacktrace
  end

  # docs/snapdiff.md calls SnapDiff::Error "Base class for every error this
  # gem raises" -- so `rescue SnapDiff::Error` has to actually catch every
  # one of them. Discovered rather than listed: a new error class added
  # outside the hierarchy fails here instead of quietly breaking that claim
  # for adopters (WindowSizeMismatchError and DualInstallError both did).
  test "every error the gem defines inherits SnapDiff::Error" do
    plumbing = [SnapDiff::Error, SnapDiff::ErrorWithFilteredBacktrace]
    errors = SnapDiff.constants
      .map { |name| SnapDiff.const_get(name) }
      .select { |const| const.is_a?(Class) && const < StandardError } - plumbing

    assert_operator errors.size, :>=, 4, "probe should see the gem's error classes"

    errors.each do |error|
      assert_operator error, :<, SnapDiff::Error, "#{error} must inherit SnapDiff::Error"
    end
  end
end
