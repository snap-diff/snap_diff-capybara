# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/difference"

module Capybara::Screenshot::Diff
  class DifferenceTest < ActiveSupport::TestCase
    class WithFailedByTest < DifferenceTest
      setup do
        @difference = Difference.new(nil, {}, nil, { different_dimensions: [] })
      end

      test 'it is different' do
        assert_predicate @difference, :different?
      end

      test 'it is failed' do
        assert_predicate @difference, :failed?
      end
    end
  end
end
