# frozen_string_literal: true

require "test_helper"

# The canonical half of what used to be errors_alias_test.rb: the shape of
# the SnapDiff error hierarchy itself, which outlives the v1 aliases. The
# `CapybaraScreenshotDiff::*` alias half stayed behind in
# test/legacy/errors_alias_test.rb and goes with the v1 trees in 2.1.
class ErrorsTest < ActiveSupport::TestCase
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
