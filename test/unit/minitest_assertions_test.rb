# frozen_string_literal: true

require "test_helper"

module CapybaraScreenshotDiff
  class MinitestAssertionsTest < ActiveSupport::TestCase
    # Runs a throwaway ::Minitest::Test that takes a single screenshot, so we can
    # inspect how before_teardown resolved (passed/skipped/failed) without polluting
    # the outer test's own assertions/reporting.
    #
    # @param teardown [Proc, nil] optional replacement `teardown` method, to
    #   simulate a user teardown that runs after `before_teardown`. Calls
    #   `super()` first so DSLStub's own cleanup still happens.
    def run_inner_test(teardown: nil, &block)
      test_class = Class.new(::Minitest::Test) do
        include CapybaraScreenshotDiff::Minitest::Assertions
        include CapybaraScreenshotDiff::DSLStub

        define_method(:test_it, &block)
        define_method(:teardown, &teardown) if teardown
      end
      test_class.new(:test_it).run
    end

    test "#before_teardown skips the test when pending_if_new is enabled and a screenshot has no baseline" do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        SnapDiff.config.stub(:pending_if_new, true) do
          result = run_inner_test { screenshot("a") }

          assert_predicate result, :skipped?
          assert_equal(
            "No baseline for: a. Commit the captured screenshots to record them.",
            result.failures.first.message
          )
        end
      end
    end

    test "#screenshot and #assert_no_screenshot_changes count Minitest assertions" do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        result = run_inner_test do
          screenshot("a")
          assert_no_screenshot_changes("b")
        end

        assert_predicate result, :passed?
        assert_equal 2, result.assertions
      end
    end

    test "#before_teardown does not mask a real teardown error behind a pending skip" do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        SnapDiff.config.stub(:pending_if_new, true) do
          result = run_inner_test(teardown: proc {
            super()
            raise "boom from teardown"
          }) { screenshot("a") }

          refute_predicate result, :skipped?
          assert_predicate result, :error?
        end
      end
    end

    test "#before_teardown does not skip the test when pending_if_new is disabled" do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        SnapDiff.config.stub(:pending_if_new, false) do
          result = run_inner_test { screenshot("a") }

          assert_predicate result, :passed?
        end
      end
    end
  end
end
