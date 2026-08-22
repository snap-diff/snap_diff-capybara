# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/difference"

module Capybara::Screenshot::Diff
  class DifferenceTest < ActiveSupport::TestCase
    setup do
      @difference = SnapDiff::ComparisonResult.new(nil, {}, nil, {different_dimensions: []})
    end

    test "#different? returns true when images have different dimensions" do
      assert_predicate @difference, :different?
    end

    test "#failed? returns true when images have different dimensions" do
      assert_predicate @difference, :failed?
    end

    test "#inspect is a one-line summary with the difference metrics" do
      line = @difference.inspect

      assert_includes line, "different=true"
      assert_includes line, "failed_by="
      assert_includes line, "area_size=0"
      assert_includes line, "difference_level="
      assert_not_includes line, "\n"
    end
  end
end
