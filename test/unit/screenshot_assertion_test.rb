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
    include CapybaraScreenshotDiff::DSL
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
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :a)

        assert_matches_screenshot(snap.full_name) # delayed by default
        assert comparison_for(snap.full_name).base_image_path.exist?, "verify has not run yet: base image must still be present"

        CapybaraScreenshotDiff.verify

        assert_not snap.base_path.exist?, "verify must archive the baseline of a passing assertion"
        assert_predicate snap.path, :exist?
      end
    end

    test "verify keeps baselines of failing delayed assertions end-to-end" do
      Capybara::Screenshot::Diff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :b)

        assert_matches_screenshot(snap.full_name) # delayed by default

        assert_raises(CapybaraScreenshotDiff::ExpectationNotMet) { CapybaraScreenshotDiff.verify }

        assert snap.base_path.exist?, "base image must be kept for the reporter on failure"
      end
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
