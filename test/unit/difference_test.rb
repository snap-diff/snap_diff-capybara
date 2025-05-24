# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/difference"

module Capybara::Screenshot::Diff
  class DifferenceTest < ActiveSupport::TestCase
    setup do
      @difference = Difference.new(nil, {}, nil, {different_dimensions: []})
    end

    test "#different? returns true when images have different dimensions" do
      assert_predicate @difference, :different?
    end

    test "#failed? returns true when images have different dimensions" do
      assert_predicate @difference, :failed?
    end
  end
end
