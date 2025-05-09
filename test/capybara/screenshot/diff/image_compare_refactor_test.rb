# frozen_string_literal: true

require "test_helper"
require "minitest/stub_const"
require_relative "test_doubles"

module Capybara
  module Screenshot
    module Diff
      class ImageCompareRefactorTest < ActionDispatch::IntegrationTest
        include CapybaraScreenshotDiff::DSLStub
        include TestDoubles

        test "when comparing identical images then quick_equal? returns true and different? returns false" do
          # Setup
          comparison = make_comparison(:a, :a)

          # Action & Verify
          assert_predicate comparison, :quick_equal?
          assert_not_predicate comparison, :different?
        end

        test "when comparing different images then quick_equal? returns false and different? returns true" do
          # Setup
          comparison = make_comparison(:a, :b)

          # Action & Verify
          assert_not_predicate comparison, :quick_equal?
          assert_predicate comparison, :different?
        end

        test "when images have different dimensions then dimensions_changed? returns true" do
          # Setup
          comparison = make_comparison(:portrait, :a)

          # Action
          comparison.processed

          # Verify
          assert_predicate comparison, :dimensions_changed?
          assert_kind_of Reporters::Default, comparison.reporter
        end
      end
    end
  end
end
