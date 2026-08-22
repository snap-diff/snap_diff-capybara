# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff"

module SnapDiff
  # Pins the baseline-archiving side effect of the verify flow: when a
  # comparison passes, the base image is moved over the actual image
  # (the baseline is "committed" and the temp base copy disappears).
  # These guards protect the file-level behavior while the mutation is
  # extracted from the read path into an explicit archive step.
  class ScreenshotAssertionTest < ActiveSupport::TestCase
    include SnapDiff::DSL
    include CapybaraScreenshotDiff::DSLStub

    test "#validate! archives the baseline when the comparison passes" do
      comparison = make_comparison(:a, :a)
      assertion = build_assertion(comparison)

      assertion.validate!

      assert_not comparison.base_image_path.exist?, "base image must be archived (moved over the actual image) on pass"
      assert_predicate comparison.image_path, :exist?
    end

    test "#validate! keeps the baseline and raises when the comparison fails" do
      comparison = make_comparison(:a, :b)
      assertion = build_assertion(comparison)

      assert_raises(CapybaraScreenshotDiff::ExpectationNotMet) { assertion.validate! }

      assert comparison.base_image_path.exist?, "base image must be kept for the reporter on failure"
    end

    test "verify archives baselines of passing delayed assertions end-to-end" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :a)

        assert_matches_screenshot(snap.full_name) # delayed by default
        assert comparison_for(snap.full_name).base_image_path.exist?, "verify has not run yet: base image must still be present"

        CapybaraScreenshotDiff.verify

        assert_not snap.base_path.exist?, "verify must archive the baseline of a passing assertion"
        assert_predicate snap.path, :exist?
      end
    end

    test "verify keeps baselines of failing delayed assertions end-to-end" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :b)

        assert_matches_screenshot(snap.full_name) # delayed by default

        assert_raises(CapybaraScreenshotDiff::ExpectationNotMet) { CapybaraScreenshotDiff.verify }

        assert snap.base_path.exist?, "base image must be kept for the reporter on failure"
      end
    end

    test "#archive_baseline! moves the base image over the actual image and is idempotent" do
      comparison = make_comparison(:a, :a)
      assertion = build_assertion(comparison)

      assertion.archive_baseline!

      assert_not comparison.base_image_path.exist?
      assert_predicate comparison.image_path, :exist?

      assertion.archive_baseline! # second call is a no-op

      assert_predicate comparison.image_path, :exist?
    end

    test "#archive_baseline! keeps the baseline when the comparison differs" do
      comparison = make_comparison(:a, :b)
      assertion = build_assertion(comparison)

      assertion.archive_baseline!

      assert comparison.base_image_path.exist?
    end

    test "#inspect is a one-line summary that does not run the comparison" do
      comparison = make_comparison(:a, :b)
      assertion = build_assertion(comparison, name: "widget")

      line = assertion.inspect

      assert_includes line, '"widget"'
      assert_includes line, "pending"
      assert_includes line, comparison.image_path.to_s
      assert_includes line, comparison.base_image_path.to_s
      assert_not_includes line, "\n"
      assert_not comparison.processed?, "#inspect must not trigger the comparison"
    end

    test "#inspect shows the verified state after the comparison ran" do
      comparison = make_comparison(:a, :b)
      assertion = build_assertion(comparison)
      assertion.validate

      assert_includes assertion.inspect, "different"

      assert_includes SnapDiff::ScreenshotAssertion.new("fresh").inspect, "no comparison"
    end

    private

    def build_assertion(comparison, name: "name")
      SnapDiff::ScreenshotAssertion.new(name).tap do |assertion|
        assertion.compare = comparison
        assertion.caller = ["my_test.rb:42"]
      end
    end

    def comparison_for(name)
      CapybaraScreenshotDiff.assertions.find { |assertion| assertion.name == name }.compare
    end
  end
end
