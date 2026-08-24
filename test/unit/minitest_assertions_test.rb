# frozen_string_literal: true

require "test_helper"

class MinitestAssertionsTest < ActiveSupport::TestCase
  # Runs a throwaway ::Minitest::Test that takes a single screenshot, so we can
  # inspect how before_teardown resolved (passed/skipped/failed) without polluting
  # the outer test's own assertions/reporting.
  #
  # Rails 7.2+ only. `defined?` rather than a version comparison: the
  # question is whether the constant is there to prepend, and edge/main can
  # move independently of the version string.
  RAILS_HAS_ASSERTION_ALARM = defined?(ActiveSupport::Testing::TestsWithoutAssertions)

  # @param teardown [Proc, nil] optional replacement `teardown` method, to
  #   simulate a user teardown that runs after `before_teardown`. Calls
  #   `super()` first so DSLStub's own cleanup still happens.
  # @param like_rails [Boolean] prepend the module Rails prepends into every
  #   ActiveSupport::TestCase, to observe its missing-assertions alarm.
  def run_inner_test(teardown: nil, like_rails: false, &block)
    # Without the module there is no alarm to observe, and running anyway would
    # assert that a thing which cannot fire did not fire -- green for the wrong
    # reason, which is the failure mode this whole release exists to remove.
    skip "ActiveSupport::Testing::TestsWithoutAssertions is Rails 7.2+" if like_rails && !RAILS_HAS_ASSERTION_ALARM

    test_class = Class.new(::Minitest::Test) do
      # The real thing, not a stand-in: Rails prepends exactly this,
      # unconditionally, at active_support/test_case.rb:205 -- but only since
      # Rails 7.2. On 7.1 the constant does not exist, so the alarm this test
      # observes is simply not a feature of that version. Skip rather than
      # stub: a hand-rolled stand-in would assert that OUR code cooperates
      # with a module Rails never prepends there, which proves nothing.
      prepend ActiveSupport::Testing::TestsWithoutAssertions if like_rails && RAILS_HAS_ASSERTION_ALARM

      include SnapDiff::Minitest::Assertions
      include DSLStub

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

  # Issue #270. The counter was bumped before the `active?` guard inside
  # `super`, so with screenshots disabled a test whose only assertion was a
  # screenshot reported `1 runs, 1 assertions, 0 failures` -- nothing
  # captured, nothing compared, and a green line claiming otherwise.
  test "a disabled screenshot is not counted as a Minitest assertion" do
    SnapDiff.config.stub(:active?, false) do
      result = run_inner_test { screenshot("a") }

      assert_predicate result, :passed?
      assert_equal 0, result.assertions, "nothing was captured and nothing was compared"
    end
  end

  # The payoff: Rails prepends TestsWithoutAssertions into every
  # ActiveSupport::TestCase, so a correct count turns Rails itself into a
  # free per-test alarm for exactly this case.
  test "Rails' missing-assertions alarm fires when the only assertion was a disabled screenshot" do
    SnapDiff.config.stub(:active?, false) do
      _out, err = capture_io do
        run_inner_test(like_rails: true) { screenshot("a") }
      end

      assert_match(/Test is missing assertions: `test_it`/, err)
    end
  end

  test "Rails' missing-assertions alarm stays quiet for a test with other assertions" do
    SnapDiff.config.stub(:active?, false) do
      _out, err = capture_io do
        run_inner_test(like_rails: true) do
          screenshot("a")
          assert true
        end
      end

      refute_match(/Test is missing assertions/, err,
        "the test asserted something; the disabled screenshot is not the whole story")
    end
  end

  # And the alarm must not fire when screenshots ARE active: the screenshot
  # is the assertion then.
  test "Rails' missing-assertions alarm stays quiet for an active screenshot" do
    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      _out, err = capture_io do
        run_inner_test(like_rails: true) { screenshot("a") }
      end

      # Not assert_empty: the no-committed-baseline notice shares this stream.
      refute_match(/Test is missing assertions/, err)
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
